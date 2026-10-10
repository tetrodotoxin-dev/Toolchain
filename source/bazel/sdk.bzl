# Copyright (c) 2023-present Matt Kaes and contributors

"""Import a release's headers and one selected library linkage.

Each release tag supplies checksums for headers and platform archives, using
keys such as linux-x86_64-v3-shared and linux-x86_64-v3-static. Linkage defaults
to shared. Selecting static also publishes the project's STATIC definition.
Declare public dependencies in deps and private link requirements in
implementation_deps. Private dependency headers and definitions stay inside
their own SDK, while their libraries remain available to consumers.
Bundled runtime libraries are imported from the selected archive automatically.
An explicitly declared SDK dependency supplies overlapping runtime libraries
when their recorded contents match. Incompatible copies fail the import.
Component tags bind consumer-owned repository labels to one component. Sibling
component edges come from the archive metadata and remain independent of those
repository mappings.
Every platform archive carries sdk.json as the complete binary, runtime,
definition, linker-option and component schema for this importer.
"""

load(":toolchains/platforms.bzl", "PLATFORMS")

_PLATFORMS = {name: str(target.condition) for name, target in PLATFORMS.items()}

def _runtime(ctx, metadata, platform):
    """Reuse declared SDK dependencies before importing bundled copies.

    Args:
        ctx: Repository context with the explicitly declared dependency labels.
        metadata: The selected archive's library records and content digests.
        platform: Archive platform whose dependency metadata is being compared.

    Returns:
        Bundled libraries that still need their own C++ import target.
    """
    provided = {}
    for dependency in ctx.attr.deps + ctx.attr.implementation_deps:
        label = Label(dependency)
        manifest = ctx.path(label.same_package_label(platform + "/sdk.json"))
        if manifest.exists:
            supplied = json.decode(ctx.read(manifest))

            # Header targets supply their compilation interface. Library and
            # component targets additionally carry the SDK's common binary.
            if supplied["project"] != label.name.upper().replace("-", "_").replace(".", "_") and label.name not in supplied["components"]:
                continue
            for path, digest in supplied["sha256"].items():
                if path in provided and provided[path] != digest:
                    fail("Conflicting SDK dependency contents for " + platform + "/" + path)
                provided[path] = digest
    runtime = []
    for library in metadata["runtime"]:
        if library["library"] in provided:
            for path in library.values():
                if path and (not provided.get(path) or metadata["sha256"].get(path) != provided[path]):
                    fail("Bundled runtime disagrees with a declared SDK dependency: " + platform + "/" + path)
        else:
            runtime.append({key: platform + "/" + path if path else None for key, path in library.items()})
    return runtime

def _sdk(ctx):
    """Import a pinned release's headers and libraries as C++ targets.

    Args:
        ctx: Repository context with release identity, archive checksums and
            dependency labels for the generated headers target.
    """
    if "headers" not in ctx.attr.archives:
        fail("An SDK pin must include its shared headers archive")
    selected = {"headers": "headers"}
    for platform in _PLATFORMS:
        archive = platform + "-" + ctx.attr.linkage
        if archive in ctx.attr.archives:
            selected[platform] = archive
    if len(selected) == 1:
        fail("No platform archives supply the requested " + ctx.attr.linkage + " linkage")
    for output, archive in selected.items():
        ctx.download_and_extract(
            url = "https://github.com/tetrodotoxin-dev/" + ctx.attr.project + "/releases/download/v" + ctx.attr.version + "/" + ctx.attr.library + "-" + ctx.attr.version + "-" + archive + ".zip",
            sha256 = ctx.attr.archives[archive],
            output = output,
        )
    for path in [
        "toolchain/export.h",
        "toolchain/memory/lifetime.hpp",
        "toolchain/toolchain.h",
        "toolchain/toolchain.hpp",
    ]:
        if not ctx.path("headers/include/" + path).exists:
            fail("SDK headers archive is missing " + path)
    static_libraries = {}
    libraries = {}
    interfaces = {}
    defines = {}
    linkopts = {}
    runtime = {}
    binaries = {}
    components = {}
    for platform, condition in _PLATFORMS.items():
        if platform not in selected:
            continue
        manifest = ctx.path(platform + "/sdk.json")
        if not manifest.exists:
            fail("SDK archive has no metadata for " + platform)
        metadata = json.decode(ctx.read(manifest))
        if metadata["linkage"] != ctx.attr.linkage:
            fail("SDK linkage disagrees with its pin for " + platform)
        binary = platform + "/" + metadata["library"]
        interface = platform + "/" + metadata["interface"] if metadata["interface"] else None
        project = ctx.attr.library.upper().replace("-", "_").replace(".", "_")
        if metadata["project"] != project:
            fail("SDK project identity disagrees with its release name for " + platform)
        if not ctx.path(binary).exists or (interface and not ctx.path(interface).exists):
            fail("SDK archive is missing its declared linker output for " + platform)
        static = ctx.attr.linkage == "static"
        static_libraries[condition] = binary if static else None
        libraries[condition] = None if static else binary
        interfaces[condition] = interface
        defines[condition] = metadata["defines"]
        linkopts[condition] = metadata["linkopts"]
        binaries[condition] = [binary] + [platform + "/" + library["library"] for library in metadata["runtime"]]
        runtime[condition] = _runtime(ctx, metadata, platform)
        for name, component in metadata["components"].items():
            if name in [ctx.attr.library, "headers", "build"] or name.startswith("runtime_"):
                fail("SDK component conflicts with a reserved target name: " + name)
            if "dependencies" not in component:
                fail("SDK component has no dependency metadata: " + name)
            sibling_dependencies = component["dependencies"]
            if name not in components:
                components[name] = {
                    "headers": {},
                    "defines": {},
                    "sibling_dependencies": sibling_dependencies,
                }
            elif components[name]["sibling_dependencies"] != sibling_dependencies:
                fail("SDK platforms disagree on dependencies for component " + name)
            components[name]["headers"][condition] = ["headers/include/" + path for path in component["headers"]]
            components[name]["defines"][condition] = component["defines"]
        for library in runtime[condition]:
            for path in library.values():
                if path and not ctx.path(path).exists:
                    fail("SDK archive is missing its declared runtime file: " + path)
    unknown = [name for name in ctx.attr.component_deps if name not in components]
    if unknown:
        fail("Component dependencies name components absent from the SDK: " + str(unknown))
    for name, component in components.items():
        siblings = component["sibling_dependencies"]
        unknown = [dependency for dependency in siblings if dependency not in components]
        if unknown:
            fail("SDK component " + name + " names missing siblings: " + str(unknown))
        component["dependencies"] = [":" + dependency for dependency in siblings] + ctx.attr.component_deps.get(name, [])
    ctx.template("BUILD.bazel", ctx.attr._template, substitutions = {
        "{dependencies}": repr(ctx.attr.deps),
        "{implementation_dependencies}": repr(ctx.attr.implementation_deps),
        "{library}": repr(ctx.attr.library),
        "{static_libraries}": repr(static_libraries),
        "{shared_libraries}": repr(libraries),
        "{interface_libraries}": repr(interfaces),
        "{defines}": repr(defines),
        "{linkopts}": repr(linkopts),
        "{runtime}": repr(runtime),
        "{binaries}": repr(binaries),
        "{components}": repr(components),
    }, executable = False)

_sdk_repository = repository_rule(implementation = _sdk, attrs = {
    "library": attr.string(mandatory = True),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "archives": attr.string_dict(mandatory = True),
    "deps": attr.string_list(),
    "component_deps": attr.string_list_dict(),
    "implementation_deps": attr.string_list(),
    "linkage": attr.string(default = "shared", values = ["static", "shared"]),
    "_template": attr.label(default = Label("//source/bazel:release/sdk.BUILD.tpl")),
})

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
                fail("Conflicting dependencies for SDK component " + component.release + ":" + component.name)
            component_deps[key] = dependencies

    seen = {}
    for module in ctx.modules:
        for release in module.tags.release:
            pin = (release.project, release.version, release.archives, release.deps, release.implementation_deps, release.linkage)
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
            _sdk_repository(name = release.name, library = release.name, project = release.project, version = release.version, archives = release.archives, deps = [str(dep) for dep in release.deps], component_deps = scoped, implementation_deps = [str(dep) for dep in release.implementation_deps], linkage = release.linkage)
    unknown = [release for release, _ in component_deps if release not in seen]
    if unknown:
        fail("Component dependencies name undeclared SDK releases: " + str(sorted({release: True for release in unknown})))

_release = tag_class(attrs = {
    "name": attr.string(mandatory = True),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "archives": attr.string_dict(mandatory = True),
    "deps": attr.label_list(),
    "implementation_deps": attr.label_list(),
    "linkage": attr.string(default = "shared", values = ["static", "shared"]),
})
_component = tag_class(attrs = {
    "release": attr.string(mandatory = True),
    "name": attr.string(mandatory = True),
    "deps": attr.label_list(),
})
dependencies = module_extension(
    implementation = _dependencies,
    tag_classes = {
        "component": _component,
        "release": _release,
    },
)
