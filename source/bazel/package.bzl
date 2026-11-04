# Copyright (c) 2023-present Matt Kaes and contributors

"""Package one project's headers and target linker outputs."""

load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":rules/python.bzl", "python_command")
load(":toolchains/platforms.bzl", "PLATFORMS")

_TARGETS = {name: str(target.platform) for name, target in PLATFORMS.items()}

# Bazel supplies the incoming settings as part of the transition contract. Each
# release replaces them with its platform and optimized compilation mode.
# buildifier: disable=unused-variable
def _targets(settings, attr):
    """Select an optimized build for each SDK platform.

    Args:
        settings: Incoming build settings, unused by these release selections.
        attr: Packaging rule attributes selecting the published platforms.

    Returns:
        A dictionary mapping SDK platform names to their build settings.
    """
    return {
        name: {
            "//command_line_option:platforms": [platform],
            "//command_line_option:compilation_mode": "opt",
        }
        for name, platform in _TARGETS.items()
        if name in attr.platforms
    }

_transition = transition(
    implementation = _targets,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
        "//command_line_option:compilation_mode",
    ],
)

def _binaries(target, project, linkage):
    """Select the target's link outputs and their release archive names.

    Args:
        target: Configured library target for one SDK platform.
        project: Published library name used for static archive filenames.
        linkage: Either static or shared, as declared by the packaging call.

    Returns:
        A binary, its optional import library and their archive basenames.
    """
    libraries = [
        library
        for entry in target[CcInfo].linking_context.linker_inputs.to_list()
        if entry.owner == target.label
        for library in entry.libraries
    ]

    if len(libraries) != 1:
        fail("Release target must own exactly one library: " + str(target.label))

    library = libraries[0]
    if linkage == "static":
        # PIC archives can also be linked into a consumer's plugin. A distinct
        # Windows basename keeps the archive separate from the DLL's .lib.
        binary = library.pic_static_library or library.static_library
        if not binary:
            fail("Static release target supplies no archive: " + str(target.label))

        name = (
            project + "_static.lib" if binary.extension == "lib" else "lib" + project + ".a"
        )

        return struct(
            binary = binary,
            name = name,
            interface = None,
            interface_name = None,
            alwayslink = library.alwayslink,
        )

    binary = library.resolved_symlink_dynamic_library or library.dynamic_library
    if not binary:
        fail("Shared release target supplies no shared library: " + str(target.label))

    interface = library.resolved_symlink_interface_library or library.interface_library
    if binary.extension == "dll" and not interface:
        fail(
            "Windows shared release target supplies no import library: " +
            str(target.label),
        )

    return struct(
        binary = binary,
        name = binary.basename,
        interface = interface,
        interface_name = (
            binary.basename.removesuffix(".dll") + ".lib" if interface else None
        ),
        alwayslink = False,
    )

_PublicHeadersInfo = provider(
    "Declared public header paths across ordinary dependencies.",
    fields = {
        "direct_defines": "Definitions declared directly by this target.",
        "dependencies": "Direct dependency labels of this interface.",
        "direct": "Header files declared directly by this target.",
        "entries": "Declared header files and their public include paths.",
    },
)

def _public_headers_impl(target, ctx):
    """Follow each public header declaration through one include mapping.

    Args:
        target: Configured dependency whose public interface is being visited.
        ctx: Aspect context exposing the rule's header and prefix declarations.

    Returns:
        Public header mappings, including mappings from ordinary dependencies.
    """
    if CcInfo not in target:
        return []

    context = target[CcInfo].compilation_context
    roots = (
        context.includes.to_list() +
        context.system_includes.to_list() +
        context.quote_includes.to_list()
    )

    roots = [root + "/" if root and root != "." else "" for root in roots]
    strip = getattr(ctx.rule.attr, "strip_include_prefix", "")
    prefix = getattr(ctx.rule.attr, "include_prefix", "")
    repository = (
        target.label.workspace_root + "/" if target.label.workspace_root else ""
    )

    package = target.label.package + "/" if target.label.package else ""
    strip_root = repository + (strip[1:] if strip.startswith("/") else package + strip)
    strip_root = strip_root.rstrip("/") + "/" if strip_root else ""
    headers = []
    for file in (
        getattr(ctx.rule.files, "hdrs", []) +
        getattr(ctx.rule.files, "textual_hdrs", []) +
        context.direct_private_headers
    ):
        if strip or prefix:
            if not file.path.startswith(strip_root):
                fail(
                    "Header is outside its declared strip_include_prefix: " + file.path,
                )

            path = file.path[len(strip_root):]
            path = prefix.rstrip("/") + "/" + path if prefix else path
        else:
            prefixes = [root for root in roots if file.path.startswith(root)]
            if not prefixes:
                continue

            path = file.path[len(sorted(prefixes, key = len)[-1]):]

        headers.append((file, path))

    dependencies = getattr(ctx.rule.attr, "deps", [])
    actual = getattr(ctx.rule.attr, "actual", None)
    direct_dependencies = []
    direct_defines = getattr(ctx.rule.attr, "defines", [])
    direct_dependencies_labels = [dependency.label for dependency in dependencies]
    if actual:
        dependencies = dependencies + [actual]
        if _PublicHeadersInfo in actual:
            direct_dependencies.append(actual[_PublicHeadersInfo].direct)

            direct_defines = actual[_PublicHeadersInfo].direct_defines
            direct_dependencies_labels = actual[_PublicHeadersInfo].dependencies

    direct = depset(headers, transitive = direct_dependencies)
    return [
        _PublicHeadersInfo(
            direct = direct,
            direct_defines = direct_defines,
            dependencies = direct_dependencies_labels,
            entries = depset(
                transitive = [direct] +
                             [
                                 dep[_PublicHeadersInfo].entries
                                 for dep in dependencies
                                 if _PublicHeadersInfo in dep
                             ],
            ),
        ),
    ]

_public_headers = aspect(
    implementation = _public_headers_impl,
    attr_aspects = ["deps", "actual"],
)

def _headers(target):
    """Select the public headers owned by the released target's repository.

    Args:
        target: Configured library with declared public header mappings.

    Returns:
        File and include path pairs owned by the release repository. External
        SDK headers remain represented by dependency labels.
    """
    return [
        (file, path)
        for file, path in target[_PublicHeadersInfo].entries.to_list()
        if file.owner.workspace_root == target.label.workspace_root
    ]

def _direct_headers(target):
    """Select headers declared directly by one released component.

    Args:
        target: Configured component with declared public header mappings.

    Returns:
        File and include path pairs owned directly by the component.
    """
    return [
        (file, path)
        for file, path in target[_PublicHeadersInfo].direct.to_list()
        if file.owner.workspace_root == target.label.workspace_root
    ]

def _archive_name(binary):
    """Keep a dependency archive distinct from a Windows DLL import library."""
    name = binary.basename
    for suffix in [".pic.a", ".pic.lo", ".lo"]:
        if name.endswith(suffix):
            name = name.removesuffix(suffix) + ".a"
            break

    if name.endswith(".lo.lib"):
        name = name.removesuffix(".lo.lib") + ".lib"

    if name.endswith(".lib") and not name.endswith("_static.lib"):
        name = name.removesuffix(".lib") + "_static.lib"

    return "lib/" + name

def _relocatable(entry, description):
    """Reject flags that still name build-local inputs absent from the SDK."""
    if any(
        [
            file.path in flag
            for file in entry.additional_inputs
            for flag in entry.user_link_flags
        ],
    ):
        fail("SDK {} need relocatable linker inputs: {}".format(description, entry.owner))

def _link_inputs(target, primary):
    """Collect the completed link's flags and dependencies in one traversal.

    Shared libraries deploy beside the primary binary. Static archives retain
    their own flags and whole-archive requirement. A host interface carries link
    information without deploying the host's runtime, such as the GPU driver.
    """
    runtime = {}
    archives = {}
    system = {}
    system_options = {}
    files = []
    linkopts = []
    for entry in target[CcInfo].linking_context.linker_inputs.to_list():
        if entry.owner == target.label or not entry.libraries:
            # The primary library and flag-only inputs carry their own link
            # requirements. Action-local files such as an empty Windows DEF
            # file remain private unless a published flag names that input.
            if any([file.path in flag for file in entry.additional_inputs for flag in entry.user_link_flags]):
                fail("SDK link requirements need relocatable inputs; additional linker inputs are not packaged: " + str(target.label))

            linkopts.extend(entry.user_link_flags)

        for library in entry.libraries:
            dynamic = (
                library.resolved_symlink_dynamic_library or library.dynamic_library
            )

            static = library.pic_static_library or library.static_library
            interface = (
                library.resolved_symlink_interface_library or library.interface_library
            )

            if dynamic:
                if dynamic == primary:
                    continue

                name = "lib/" + dynamic.basename
                import_name = (
                    "lib/" + dynamic.basename.removesuffix(".dll") + ".lib" if interface else None
                )

                runtime[name] = {"library": name, "interface": import_name}
                files.append([dynamic, name])
                if interface:
                    files.append([interface, import_name])

            elif static:
                if static == primary:
                    continue

                _relocatable(entry, "static dependencies")

                name = _archive_name(static)
                record = {
                    "library": name,
                    "alwayslink": library.alwayslink,
                    "linkopts": entry.user_link_flags,
                }

                if name in archives and archives[name] != record:
                    fail("Conflicting static dependency requirements for " + name)

                archives[name] = record
                files.append([static, name])

            elif interface:
                _relocatable(entry, "system interfaces")

                name = "link/" + interface.basename

                # Different dependency paths can supply equal host interfaces
                # with different flags. Preserve each complete option group once.
                system_options.setdefault(name, {})[tuple(entry.user_link_flags)] = True
                system[name] = {"interface": name}
                files.append([interface, name])

    for name, record in system.items():
        record["linkopts"] = [flag for group in system_options[name] for flag in group]

    return struct(
        runtime = [runtime[name] for name in sorted(runtime)],
        archives = [archives[name] for name in sorted(archives)],
        system = [system[name] for name in sorted(system)],
        files = files,
        linkopts = linkopts,
    )

def _toolchain_header_path(file):
    """Return the public include path of one Toolchain compiler header."""
    marker = "source/toolchain/"
    start = file.short_path.find(marker)
    if start < 0:
        fail(
            "Toolchain compiler header has no canonical source path: " + file.short_path,
        )

    return file.short_path[start + len("source/"):]

def _component_metadata(ctx, platform, project, headers, linkage):
    """Record each component's own declarations and public dependency edges.

    The imported sibling graph reconstructs the complete header interface. Its
    per-component definitions keep static and shared annotation choices local.
    """
    component_names = ctx.attr.component_names
    component_dependencies = ctx.attr.component_dependencies
    selected_components = ctx.split_attr.components.get(platform, [])
    if not component_dependencies:
        names = {
            component.label: name
            for component, name in zip(selected_components, component_names)
        }

        component_dependencies = {}
        for component, name in zip(selected_components, component_names):
            public_dependencies = component[_PublicHeadersInfo].dependencies
            unknown = [
                dependency
                for dependency in public_dependencies
                if dependency.workspace_root == component.label.workspace_root and
                   dependency.package == component.label.package and
                   dependency not in names
            ]

            if unknown:
                fail(
                    "Component " +
                    name +
                    " depends on unpackaged siblings: " +
                    str(unknown),
                )

            component_dependencies[name] = [
                names[dependency]
                for dependency in public_dependencies
                if dependency in names
            ]

    components = {}
    for component, name in zip(selected_components, component_names):
        paths = {path: True for _, path in _direct_headers(component)}
        for file in ctx.files._toolchain_headers:
            paths[_toolchain_header_path(file)] = True

        for path in paths:
            if path not in headers:
                fail(
                    "Component header is outside the released interface: " +
                    path,
                )

        defines = [
            define
            for define in component[_PublicHeadersInfo].direct_defines
            if define != project + "_STATIC=1"
        ]

        if linkage == "static":
            defines.append(project + "_STATIC=1")

        components[name] = {
            "headers": sorted(paths),
            "defines": depset(defines).to_list(),
            "dependencies": component_dependencies[name],
        }

    return components

def _write_archives(ctx, stem, archives, inputs):
    """Pass the selected files to the pinned archive writer as one manifest."""
    outputs = [ctx.actions.declare_file(name) for name in archives]
    checksum = ctx.actions.declare_file(stem + "-sha256.txt")
    manifest = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(
        manifest,
        json.encode({output.path: archives[output.basename] for output in outputs}),
    )

    python = ctx.attr._python[platform_common.ToolchainInfo].py3_runtime
    ctx.actions.run(
        executable = python.interpreter,
        arguments = ["-I", "-B", ctx.file._writer.path, manifest.path, checksum.path],
        inputs = depset(inputs + [manifest, ctx.file._writer], transitive = [python.files]),
        outputs = outputs + [checksum],
        mnemonic = "PackageRelease",
    )

    return [
        DefaultInfo(files = depset(outputs + [checksum])),
        OutputGroupInfo(checksum = depset([checksum])),
    ]

def _package(ctx):
    """Write header and platform archives with a checksum manifest.

    Args:
        ctx: Rule context with public headers and libraries split by platform.

    Returns:
        A list containing DefaultInfo for the archives and checksum file.
    """
    stem = ctx.attr.project + "-" + ctx.attr.version
    variants = {
        linkage: getattr(ctx.split_attr, linkage)
        for linkage in ["static", "shared"]
        if getattr(ctx.attr, linkage)
    }

    headers = {}
    for targets in variants.values():
        for target in targets.values():
            for file, path in _headers(target):
                if path in headers and headers[path] != file:
                    fail("Release variants supply different headers for " + path)

                headers[path] = file

    # Every SDK carries Toolchain's compiler vocabulary and annotation
    # contract. setdefault preserves a project owned copy at the same path.
    for file in ctx.files._toolchain_headers:
        headers.setdefault(_toolchain_header_path(file), file)

    license = [[ctx.file.license.path, "LICENSE"]]
    header_members = [[file.path, "include/" + path] for path, file in headers.items()]
    header_members.extend(license)

    archives = {stem + "-headers.zip": header_members}

    inputs = headers.values() + [ctx.file.license]
    for linkage, targets in variants.items():
        for platform, target in targets.items():
            files = _binaries(target, ctx.attr.project, linkage)
            dependencies = _link_inputs(target, files.binary)
            project = ctx.attr.project.upper().replace("-", "_").replace(".", "_")
            defines = target[CcInfo].compilation_context.defines.to_list()
            if linkage == "static" and project + "_STATIC=1" not in defines:
                fail(
                    "Static release project must match its static_library project: " +
                    project,
                )

            archive = stem + "-" + platform + "-" + linkage

            # Each component records only its own declarations. Sibling edges
            # reconstruct the complete public interface in the imported SDK.
            components = _component_metadata(ctx, platform, project, headers, linkage)
            metadata = ctx.actions.declare_file(archive + ".json")
            ctx.actions.write(
                metadata,
                json.encode(
                    {
                        "project": project,
                        "linkage": linkage,
                        "library": "lib/" + files.name,
                        "interface": (
                            "lib/" + files.interface_name if files.interface else None
                        ),
                        "defines": defines,
                        "linkopts": dependencies.linkopts,
                        "alwayslink": files.alwayslink,
                        "runtime": dependencies.runtime,
                        "archives": dependencies.archives,
                        "system": dependencies.system,
                        "components": components,
                    },
                ),
            )

            members = [[file.path, path] for file, path in dependencies.files] + [
                [files.binary.path, "lib/" + files.name],
                [metadata.path, "sdk.json"],
            ]

            inputs.extend([file for file, _ in dependencies.files])
            inputs.extend([files.binary, metadata])
            if files.interface:
                members.append([files.interface.path, "lib/" + files.interface_name])
                inputs.append(files.interface)

            archives[archive + ".zip"] = members + license

    return _write_archives(ctx, stem, archives, inputs)

_package_release = rule(
    implementation = _package,
    attrs = {
        "static": attr.label(
            cfg = _transition,
            providers = [CcInfo],
            aspects = [_public_headers],
        ),
        "shared": attr.label(
            cfg = _transition,
            providers = [CcInfo],
            aspects = [_public_headers],
        ),
        "components": attr.label_list(
            cfg = _transition,
            providers = [CcInfo],
            aspects = [_public_headers],
        ),
        "component_names": attr.string_list(),
        "component_dependencies": attr.string_list_dict(),
        "project": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "license": attr.label(mandatory = True, allow_single_file = True),
        "platforms": attr.string_list(mandatory = True),
        "_toolchain_headers": attr.label_list(
            default = [Label("//source:header_files")],
            allow_files = True,
        ),
        "_writer": attr.label(
            default = Label("//source/bazel:release/package.py"),
            allow_single_file = True,
        ),
        "_python": attr.label(
            default = Label("@rules_python//python:current_py_toolchain"),
            cfg = "exec",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def package(
        name = "sdk",
        module = None,
        components = {},
        static = None,
        shared = None,
        linkage = None,
        visibility = ["//visibility:public"],
        tags = ["manual"],
        **kwargs):
    """Publish a module's library, component interfaces and SDK release command.

    Declared component labels supply their own interfaces and dependency edges.
    A dictionary retains the source-package form, mapping names to sibling
    dependencies and exposing those interfaces beside the selected runtime.
    These C++ header interfaces also materialize the include trees used by
    editor navigation. Both forms publish the same component metadata for
    archive consumers.

    `bazel run :sdk` formats the workspace, runs optimized host tests and builds
    the selected archives. It then archives the clean Git commit as the release's
    source snapshot. A failed stage stops the release. Formatting changes must
    be committed before the release can finish.

    Args:
        name: SDK release command name, defaulting to sdk.
        module: Published library identity, defaulting to the Bazel module name.
        components: Declared component labels, or component names mapped to
            sibling dependencies for interfaces supplied by //source.
        static: Static runtime target. With neither variant supplied, the
            selected linkage uses //source:<module>.
        shared: Optional shared runtime target. Supply both variants to package
            both while selecting one for source consumers through linkage.
        linkage: Linkage used by root library and component consumers. Defaults
            to static when available, otherwise shared.
        visibility: Visibility of the published targets, defaulting to public.
        tags: SDK target tags. The default manual tag keeps cross compilation
            out of wildcard builds while permitting an explicit :sdk build.
        **kwargs: Additional release attributes such as selected platforms.
    """
    module = module or native.module_name()
    linkage = linkage or ("shared" if shared and not static else "static")
    if linkage not in ["static", "shared"]:
        fail("package linkage must be static or shared")

    if not static and not shared:
        if linkage == "static":
            static = "//source:" + module
        else:
            shared = "//source:" + module

    runtime = static if linkage == "static" else shared
    if not runtime:
        fail("package requires a target for its selected " + linkage + " linkage")

    common = {
        key: kwargs[key]
        for key in ["testonly", "target_compatible_with", "compatible_with"]
        if key in kwargs
    }

    if runtime not in [":" + module, "//:" + module]:
        native.alias(name = module, actual = runtime, visibility = visibility, **common)

    if static and module == native.module_name():
        # Web validation is a standalone Node program and folds the project's
        # static runtime even when ordinary source consumers select the shared
        # variant. Validation defaults to the repository's primary module.
        # Additional SDK packages keep their own runtime targets without
        # competing for that primary module's private validation alias.
        native.alias(
            name = "_validation_static",
            actual = static,
            visibility = ["//visibility:private"],
            **common
        )

    definitions = (
        [module.upper().replace("-", "_").replace(".", "_") + "_STATIC=1"] if linkage == "static" else []
    )

    component_dependencies = None
    if type(components) == "dict":
        component_dependencies = components
        component_targets = {
            "//source:" + component: component
            for component in components
        }

        for component in components:
            cc_library(
                name = component,
                deps = ["//source:" + component],
                implementation_deps = [runtime],
                defines = definitions,
                visibility = visibility,
                **common
            )
    else:
        component_targets = {
            component: native.package_relative_label(component).name
            for component in components
        }

    archives = "_" + name + "_archives"
    package_release(
        name = archives,
        project = module,
        components = component_targets,
        component_dependencies = component_dependencies,
        static = static,
        shared = shared,
        visibility = ["//visibility:private"],
        tags = tags,
        **kwargs
    )

    sdk(
        name = name,
        archives = ["//" + native.package_name() + ":" + archives],
        visibility = visibility,
        tags = tags,
    )

def sdk(name = "sdk", archives = [], **kwargs):
    """Release the selected archives through one format, host test and snapshot pass.

    Archive targets retain their library identities and platform selections.
    The command builds them together after the host tests pass, then snapshots
    the repository's clean commit. An empty selection releases source alone.
    """
    python_command(
        name = name,
        script = Label("//source/bazel:release/sdk.py"),
        arguments = [
                        native.module_name(),
                        native.module_version(),
                        "$(execpath //:format)",
                    ] +
                    archives,
        data = ["//:format"],
        **kwargs
    )

def package_release(
        name,
        static = None,
        shared = None,
        project = None,
        platforms = None,
        components = {},
        component_dependencies = None,
        **kwargs):
    """Package static and shared libraries with their public headers.

    Called from the repository root to build each supplied target for the
    selected SDK platforms. Binary archives end in -static.zip or -shared.zip.
    Static Windows archives use _static.lib so they can share an installation
    directory with the DLL's import library.
    Each archive preserves public definitions and the target's linkopts.
    Declared transitive shared libraries and their import libraries accompany
    either linkage in lib/. System libraries supplied by the platform remain
    platform requirements. Static archives required by the final link accompany
    the release with their linker options and whole-archive requirements.
    Static dependencies absorbed by a shared library are part of that binary.
    The archive writer checks repeated filenames for identical contents, so
    conflicting libraries fail packaging instead of replacing one another.
    Linkopts must remain valid in an extracted SDK. Linker scripts and other
    additional linker inputs require explicit distribution support. Dependency
    SDKs provide their link requirements through the importer's deps.

    A header defines TOOLCHAIN_PRIVATE_HEADER as 1 before its first include to
    remain local to source compilation. Header archives and component metadata
    omit marked files. Every include from a published header must resolve to
    another published header; packaging rejects dependencies on marked files.

    Args:
        name: Release packaging target name.
        static: Optional static_library target. Supply at least one variant.
        shared: Optional shared_library target. Supply at least one variant.
        project: Published name and EXPORTED identifier before uppercasing,
            defaulting to the module name. Match the library macros' project.
        platforms: Platform names to publish, defaulting to all SDK platforms.
        components: Header interface targets mapped to public SDK target names.
            Each component links the release binary and exposes the selected
            target's public headers and definitions. These targets describe
            headers independently of the release's static or shared linkage.
        component_dependencies: Optional public component names mapped to their
            sibling requirements. Omit to follow the declared dependency graph.
        **kwargs: Common rule attributes such as visibility, tags and testonly.
    """
    if not static and not shared:
        fail("package_release requires a static or shared library")

    component_names = components.values()
    if component_dependencies != None and sorted(
        component_dependencies.keys(),
    ) != sorted(component_names):
        fail("component_dependencies must describe every packaged component")

    for component, dependencies in (component_dependencies or {}).items():
        unknown = [
            dependency
            for dependency in dependencies
            if dependency not in component_names
        ]

        if unknown:
            fail(
                "component " + component + " names unpackaged siblings: " + str(unknown),
            )

        if component in dependencies:
            fail("component cannot depend on itself: " + component)

    selected = _TARGETS.keys() if platforms == None else platforms
    if not selected or any([platform not in _TARGETS for platform in selected]):
        fail("platforms must select supported SDK platforms: " + str(_TARGETS.keys()))

    _package_release(
        name = name,
        static = static,
        shared = shared,
        components = components.keys(),
        component_names = components.values(),
        component_dependencies = component_dependencies or {},
        project = project or native.module_name(),
        platforms = selected,
        version = native.module_version(),
        license = "//:LICENSE",
        **kwargs
    )
