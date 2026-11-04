# Copyright (c) 2023-present Matt Kaes and contributors

"""Import a release's headers and one selected library linkage.

Each release tag supplies checksums for headers and platform archives, using
keys such as linux-x86_64-v3-shared and linux-x86_64-v3-static. Linkage defaults
to shared. Selecting static also publishes the project's STATIC definition.
Declare public dependencies in deps and private link requirements in
implementation_deps. Private dependency headers and definitions stay inside
their own SDK, while their libraries remain available to consumers.
Bundled runtime libraries are imported from the selected archive automatically.
Static dependencies accompany their consuming archive and retain their own
link requirements. System-provided libraries carry their link interfaces under
link/; the host supplies their runtime implementations. Earlier archives with
no system records continue to use their existing library declarations.
A release's `name` identifies its Bazel repository; `library`
identifies the published artifact. Separate repository names can therefore
select static and shared variants of the same release in one build. Library
targets choose those repositories through deps and implementation_deps.
An explicitly declared SDK dependency supplies overlapping runtime libraries
when their recorded contents match. Incompatible copies fail the import.
Components preserve these published identities through their link dependencies.
Matching runtime payloads use one library input when components are combined;
conflicting contents or linker interfaces fail before linking. Each component
keeps its declared header scope.
Component tags bind consumer-owned repository labels to one component. Sibling
component edges come from the archive metadata and remain independent of those
repository mappings.
Every platform archive carries sdk.json as the complete binary, runtime,
definition, linker-option and component schema for this importer.
"""

load(":toolchains/platforms.bzl", "PLATFORMS")

_PLATFORMS = {name: str(target.condition) for name, target in PLATFORMS.items()}

def _provided(ctx, platform):
    """Collect binaries and static link requirements from declared SDKs.

    Args:
        ctx: Repository context with the explicitly declared dependency labels.
        platform: Archive platform whose dependency metadata is being compared.

    Returns:
        File digests and static archive requirements.
    """
    provided = {}
    archives = {}
    for dependency in ctx.attr.deps + ctx.attr.implementation_deps:
        label = Label(dependency)
        manifest = ctx.path(label.same_package_label(platform + "/sdk.json"))
        if manifest.exists:
            supplied = json.decode(ctx.read(manifest))

            # Header targets supply their compilation interface. Library and
            # component targets additionally carry the SDK's common binary.
            if (
                supplied["project"] !=
                label.name.upper().replace("-", "_").replace(".", "_") and
                label.name not in supplied["components"]
            ):
                continue

            for path, digest in supplied["sha256"].items():
                if path in provided and provided[path] != digest:
                    fail(
                        "Conflicting SDK dependency contents for " +
                        platform +
                        "/" +
                        path,
                    )

                provided[path] = digest

            records = supplied.get("archives", [])
            if supplied["linkage"] == "static":
                records = records + [
                    {
                        "library": supplied["library"],
                        "alwayslink": supplied.get("alwayslink", False),
                        "linkopts": supplied["linkopts"],
                    },
                ]

            for library in records:
                archives[supplied["sha256"][library["library"]]] = library

    return struct(files = provided, archives = archives)

def _runtime(metadata, platform, provided):
    """Reuse declared SDK dependencies before importing bundled shared copies.

    Args:
        metadata: The selected archive's library records and content digests.
        platform: Archive platform whose dependency metadata is being compared.
        provided: File digests supplied by explicitly declared SDK dependencies.

    Returns:
        Bundled libraries that still need their own C++ import target.
    """
    runtime = []
    for library in metadata["runtime"]:
        if library["library"] in provided:
            for path in library.values():
                if path and (
                    not provided.get(path) or
                    metadata["sha256"].get(path) != provided[path]
                ):
                    fail(
                        "Bundled runtime disagrees with a declared SDK dependency: " +
                        platform +
                        "/" +
                        path,
                    )
        else:
            runtime.append(
                {
                    key: platform + "/" + path if path else None
                    for key, path in library.items()
                },
            )

    return runtime

def _archives(metadata, platform, provided):
    """Import static dependencies whose contents are absent from declared SDKs.

    Args:
        metadata: Archive records and their content digests.
        platform: SDK platform being imported.
        provided: Declared SDK binaries and their static link requirements.

    Returns:
        Static library records still required by the final consumer's link.
    """
    result = []
    for library in metadata.get("archives", []):
        path = library["library"]
        digest = metadata["sha256"][path]
        if path in provided.files and provided.files[path] != digest:
            fail(
                "Bundled archive disagrees with a declared SDK dependency: " +
                platform +
                "/" +
                path,
            )

        # The same archive may have a different build-target basename before
        # publication. Its contents establish whether the dependency supplies it.
        if digest in provided.archives:
            supplied = provided.archives[digest]
            if (
                library["alwayslink"] != supplied["alwayslink"] or
                library["linkopts"] != supplied["linkopts"]
            ):
                fail(
                    "Bundled archive link requirements disagree with a declared SDK dependency: " +
                    platform +
                    "/" +
                    path,
                )
        else:
            result.append(dict(
                library,
                library = platform + "/" + path,
                alwayslink = library["alwayslink"],
                linkopts = library["linkopts"],
            ))

    return result

def _platform(ctx, platform):
    """Validate one archive and retain its metadata as one platform record.

    Paths become repository relative here. Declared dependency SDKs supply equal
    payloads before the build macro creates imports for the remaining files.
    """
    manifest = ctx.path(platform + "/sdk.json")
    if not manifest.exists:
        fail("SDK archive has no metadata for " + platform)

    metadata = json.decode(ctx.read(manifest))
    project = ctx.attr.library.upper().replace("-", "_").replace(".", "_")
    binary = platform + "/" + metadata["library"]
    interface = (
        platform + "/" + metadata["interface"] if metadata["interface"] else None
    )

    if metadata["linkage"] != ctx.attr.linkage:
        fail("SDK linkage disagrees with its pin for " + platform)

    if metadata["project"] != project:
        fail("SDK project identity disagrees with its release name for " + platform)

    if not ctx.path(binary).exists or (interface and not ctx.path(interface).exists):
        fail("SDK archive is missing its declared linker output for " + platform)

    provided = _provided(ctx, platform)
    runtime = _runtime(metadata, platform, provided.files)
    archives = _archives(metadata, platform, provided)
    system = []
    binaries = [binary] + [
        platform + "/" + library["library"]
        for library in metadata["runtime"]
    ]

    binaries.extend(
        [
            platform + "/" + library["library"]
            for library in metadata.get("archives", [])
        ],
    )

    binaries.extend(
        [
            platform + "/" + library["interface"]
            for library in metadata.get("system", [])
        ],
    )

    for library in metadata.get("system", []):
        path = library["interface"]
        if path in provided.files and provided.files[path] != metadata["sha256"][path]:
            fail(
                "Bundled system interface disagrees with a declared SDK dependency: " +
                platform +
                "/" +
                path,
            )

        if not ctx.path(platform + "/" + path).exists:
            fail("SDK archive is missing its declared system interface: " + path)

        # Equal host interfaces can have different linker requirements. Each
        # consuming SDK retains its complete option group.
        system.append(
            {
                "interface": platform + "/" + path,
                "linkopts": library.get("linkopts", []),
            },
        )

    for library in runtime:
        for path in library.values():
            if path and not ctx.path(path).exists:
                fail("SDK archive is missing its declared runtime file: " + path)

    for library in archives:
        if not ctx.path(library["library"]).exists:
            fail(
                "SDK archive is missing its declared static dependency: " +
                library["library"],
            )

    return {
        "linkage": metadata["linkage"],
        "library": binary,
        "interface": interface,
        "defines": metadata["defines"],
        "linkopts": metadata["linkopts"],
        "alwayslink": metadata.get("alwayslink", False),
        "runtime": runtime,
        "archives": archives,
        "system": system,
        "binaries": binaries,
        "components": metadata["components"],
        "sha256": {platform + "/" + path: digest for path, digest in metadata["sha256"].items()},
    }

def _components(ctx, platforms):
    """Preserve header scope and sibling edges across every platform variant.

    Consumer-owned external labels join the recorded sibling dependencies only
    after the complete component inventory has been validated.
    """
    reserved = [ctx.attr.library, "headers", "build"]
    private_prefixes = ["runtime_", "archive_", "system_", "_sdk_"]
    components = {}
    for condition, metadata in platforms.items():
        for name, component in metadata["components"].items():
            if name in reserved or any([name.startswith(prefix) for prefix in private_prefixes]):
                fail("SDK component conflicts with a reserved target name: " + name)

            if "dependencies" not in component:
                fail("SDK component has no dependency metadata: " + name)

            siblings = component["dependencies"]
            if name not in components:
                components[name] = {
                    "headers": {},
                    "defines": {},
                    "sibling_dependencies": siblings,
                }
            elif components[name]["sibling_dependencies"] != siblings:
                fail("SDK platforms disagree on dependencies for component " + name)

            components[name]["headers"][condition] = [
                "headers/include/" + path
                for path in component["headers"]
            ]

            components[name]["defines"][condition] = component["defines"]

    unknown = [name for name in ctx.attr.component_deps if name not in components]
    if unknown:
        fail(
            "Component dependencies name components absent from the SDK: " +
            str(unknown),
        )

    for name, component in components.items():
        siblings = component["sibling_dependencies"]
        unknown = [
            dependency
            for dependency in siblings
            if dependency not in components
        ]

        if unknown:
            fail("SDK component " + name + " names missing siblings: " + str(unknown))

        component["dependencies"] = [
            ":" + dependency
            for dependency in siblings
        ] + ctx.attr.component_deps.get(name, [])

    return components

def _sdk(ctx):
    """Acquire a pinned release and declare its validated platform records."""
    if "headers" not in ctx.attr.archives:
        fail("An SDK pin must include its shared headers archive")

    selected = {"headers": "headers"}
    for platform in _PLATFORMS:
        archive = platform + "-" + ctx.attr.linkage
        if archive in ctx.attr.archives:
            selected[platform] = archive

    if len(selected) == 1:
        fail(
            "No platform archives supply the requested " + ctx.attr.linkage + " linkage",
        )

    for output, archive in selected.items():
        ctx.download_and_extract(
            url = "https://github.com/tetrodotoxin-dev/" +
                  ctx.attr.project +
                  "/releases/download/v" +
                  ctx.attr.version +
                  "/" +
                  ctx.attr.library +
                  "-" +
                  ctx.attr.version +
                  "-" +
                  archive +
                  ".zip",
            sha256 = ctx.attr.archives[archive],
            output = output,
        )

    for path in [
        "toolchain/export.h",
        "toolchain/compile/allocation.hpp",
        "toolchain/compile/source_location.hpp",
        "toolchain/memory/lifetime.hpp",
        "toolchain/toolchain.h",
        "toolchain/toolchain.hpp",
    ]:
        if not ctx.path("headers/include/" + path).exists:
            fail("SDK headers archive is missing " + path)

    platforms = {
        condition: _platform(ctx, platform)
        for platform, condition in _PLATFORMS.items()
        if platform in selected
    }

    components = _components(ctx, platforms)
    ctx.template(
        "BUILD.bazel",
        ctx.attr._template,
        substitutions = {
            "{dependencies}": repr(ctx.attr.deps),
            "{implementation_dependencies}": repr(ctx.attr.implementation_deps),
            "{library}": repr(ctx.attr.library),
            "{platforms}": repr(platforms),
            "{components}": repr(components),
        },
        executable = False,
    )

_sdk_repository = repository_rule(
    implementation = _sdk,
    attrs = {
        "library": attr.string(mandatory = True),
        "project": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "archives": attr.string_dict(mandatory = True),
        "deps": attr.string_list(),
        "component_deps": attr.string_list_dict(),
        "implementation_deps": attr.string_list(),
        "linkage": attr.string(default = "shared", values = ["static", "shared"]),
        "_template": attr.label(default = Label("//source/bazel:release/sdk.build.tpl")),
    },
)

def _dependencies(ctx):
    """Merge matching SDK pins and create one repository per release name.

    Args:
        ctx: Module extension context containing the modules' release tags.
    """
    component_deps = {}
    for module in ctx.modules:
        for component in module.tags.component:
            key = (component.release, component.name)
            dependencies = [str(dependency) for dependency in component.deps]
            if key in component_deps and component_deps[key] != dependencies:
                fail(
                    "Conflicting dependencies for SDK component " +
                    component.release +
                    ":" +
                    component.name,
                )

            component_deps[key] = dependencies

    seen = {}
    for module in ctx.modules:
        for release in module.tags.release:
            library = release.library or release.name
            pin = (
                library,
                release.project,
                release.version,
                release.archives,
                release.deps,
                release.implementation_deps,
                release.linkage,
            )

            if release.name in seen:
                if seen[release.name] != pin:
                    fail("Conflicting SDK release pins for " + release.name)

                continue

            seen[release.name] = pin

            scoped = {
                name: dependencies
                for (owner, name), dependencies in component_deps.items()
                if owner == release.name
            }

            _sdk_repository(
                name = release.name,
                library = library,
                project = release.project,
                version = release.version,
                archives = release.archives,
                deps = [str(dep) for dep in release.deps],
                component_deps = scoped,
                implementation_deps = [str(dep) for dep in release.implementation_deps],
                linkage = release.linkage,
            )

    unknown = [release for release, _ in component_deps if release not in seen]
    if unknown:
        fail(
            "Component dependencies name undeclared SDK releases: " +
            str(sorted({release: True for release in unknown})),
        )

_release = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "library": attr.string(),
        "project": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "archives": attr.string_dict(mandatory = True),
        "deps": attr.label_list(),
        "implementation_deps": attr.label_list(),
        "linkage": attr.string(default = "shared", values = ["static", "shared"]),
    },
)
_component = tag_class(
    attrs = {
        "release": attr.string(mandatory = True),
        "name": attr.string(mandatory = True),
        "deps": attr.label_list(),
    },
)
dependencies = module_extension(
    implementation = _dependencies,
    tag_classes = {
        "component": _component,
        "release": _release,
    },
)
