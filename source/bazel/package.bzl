# Copyright (c) 2023-present Matt Kaes and contributors

"""Package one project's source, headers and every target's linker outputs."""

load("@host_tools//:settings.bzl", "PYTHON")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_TARGETS = {
    "linux-x86_64-v3": str(Label("//:linux_x86_64")),
    "windows-x86_64-msvc": str(Label("//:windows_x64")),
    "wasm32-emscripten": str(Label("//:wasm32")),
}

# Bazel supplies the incoming settings even though every release selects opt.
# buildifier: disable=unused-variable
def _targets(settings, attr):
    """Select an optimized build for each SDK platform.

    Args:
        settings: Incoming build settings, unused by these release selections.
        attr: Packaging rule attributes selecting the published platforms.

    Returns:
        A dictionary mapping SDK platform names to their build settings.
    """
    return {name: {
        "//command_line_option:platforms": [platform],
        "//command_line_option:compilation_mode": "opt",
    } for name, platform in _TARGETS.items() if name in attr.platforms}

_transition = transition(
    implementation = _targets,
    inputs = [],
    outputs = ["//command_line_option:platforms", "//command_line_option:compilation_mode"],
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
    libraries = [library for entry in target[CcInfo].linking_context.linker_inputs.to_list() if entry.owner == target.label for library in entry.libraries]
    if len(libraries) != 1:
        fail("Release target must own exactly one library: " + str(target.label))
    library = libraries[0]
    if linkage == "static":
        # PIC archives can also be linked into a consumer's plugin. A distinct
        # Windows basename keeps the archive separate from the DLL's .lib.
        binary = library.pic_static_library or library.static_library
        if not binary:
            fail("Static release target supplies no archive: " + str(target.label))
        name = project + "_static.lib" if binary.extension == "lib" else "lib" + project + ".a"
        return struct(binary = binary, name = name, interface = None, interface_name = None)
    binary = library.resolved_symlink_dynamic_library or library.dynamic_library
    if not binary:
        fail("Shared release target supplies no shared library: " + str(target.label))
    interface = library.resolved_symlink_interface_library or library.interface_library
    if binary.extension == "dll" and not interface:
        fail("Windows shared release target supplies no import library: " + str(target.label))
    return struct(binary = binary, name = binary.basename, interface = interface, interface_name = binary.basename.removesuffix(".dll") + ".lib" if interface else None)

def _headers(target):
    """Collect repository headers with the include paths consumers use.

    Args:
        target: Configured target providing the C++ compilation context.

    Returns:
        A list of [File, include_path] pairs from the target's repository.
    """
    context = target[CcInfo].compilation_context
    roots = context.includes.to_list() + context.system_includes.to_list() + context.quote_includes.to_list()
    roots = [root + "/" if root and root != "." else "" for root in roots]
    headers = []
    for file in context.headers.to_list():
        if file.owner.workspace_root != target.label.workspace_root:
            continue
        prefixes = [prefix for prefix in roots if file.path.startswith(prefix)]
        if prefixes:
            prefix = sorted(prefixes, key = len)[-1]
            headers.append([file, file.path[len(prefix):]])
    return headers

def _package(ctx):
    """Write source, header and platform archives with a checksum manifest.

    Args:
        ctx: Rule context with source files and libraries split by platform.

    Returns:
        A list containing DefaultInfo for the archives and checksum file.
    """
    stem = ctx.attr.project + "-" + ctx.attr.version
    variants = {linkage: getattr(ctx.split_attr, linkage) for linkage in ["static", "shared"] if getattr(ctx.attr, linkage)}
    headers = {"toolchain/export.h": ctx.file._export}
    for targets in variants.values():
        for target in targets.values():
            for file, path in _headers(target):
                if path in headers and headers[path] != file:
                    fail("Release variants supply different headers for " + path)
                headers[path] = file
    license = [[file.path, "LICENSE"] for file in ctx.files.sources if file.short_path == "LICENSE"]
    archives = {
        stem + "-headers.zip": [[file.path, "include/" + path] for path, file in headers.items()] + license,
        stem + "-source.zip": [[file.path, file.short_path] for file in ctx.files.sources],
    }
    inputs = headers.values() + ctx.files.sources
    for linkage, targets in variants.items():
        for platform, target in targets.items():
            files = _binaries(target, ctx.attr.project, linkage)
            project = ctx.attr.project.upper().replace("-", "_").replace(".", "_")
            defines = target[CcInfo].compilation_context.defines.to_list()
            if linkage == "static" and project + "_STATIC=1" not in defines:
                fail("Static release project must match its static_library project: " + project)

            # Dependencies carry their own link requirements through SDK deps.
            # Export this target's flags once and preserve their ordering.
            linkopts = []
            for entry in target[CcInfo].linking_context.linker_inputs.to_list():
                if entry.owner == target.label:
                    # Toolchains can attach private link inputs, such as an
                    # empty Windows DEF file. Only consumer flags make those
                    # files a requirement of the imported SDK.
                    if any([file.path in flag for file in entry.additional_inputs for flag in entry.user_link_flags]):
                        fail("SDK link requirements need relocatable inputs; additional linker inputs are not packaged: " + str(target.label))
                    linkopts.extend(entry.user_link_flags)
            archive = stem + "-" + platform + "-" + linkage
            metadata = ctx.actions.declare_file(archive + ".json")
            ctx.actions.write(metadata, json.encode({
                "project": project,
                "linkage": linkage,
                "library": "lib/" + files.name,
                "interface": "lib/" + files.interface_name if files.interface else None,
                "defines": defines,
                "linkopts": linkopts,
            }))
            members = [[files.binary.path, "lib/" + files.name], [metadata.path, "sdk.json"]]
            inputs.extend([files.binary, metadata])
            if files.interface:
                members.append([files.interface.path, "lib/" + files.interface_name])
                inputs.append(files.interface)
            archives[archive + ".zip"] = members + license
    outputs = [ctx.actions.declare_file(name) for name in archives]
    checksum = ctx.actions.declare_file(stem + "-sha256.txt")
    manifest = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(manifest, json.encode({output.path: archives[output.basename] for output in outputs}))
    ctx.actions.run(
        executable = PYTHON,
        arguments = [ctx.file._writer.path, manifest.path, checksum.path],
        inputs = depset(inputs + [manifest, ctx.file._writer]),
        outputs = outputs + [checksum],
        mnemonic = "PackageRelease",
    )
    return [DefaultInfo(files = depset(outputs + [checksum]))]

_package_release = rule(implementation = _package, attrs = {
    "static": attr.label(cfg = _transition, providers = [CcInfo]),
    "shared": attr.label(cfg = _transition, providers = [CcInfo]),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "sources": attr.label_list(allow_files = True),
    "platforms": attr.string_list(mandatory = True),
    "_export": attr.label(default = Label("//source:toolchain/export.h"), allow_single_file = True),
    "_writer": attr.label(default = Label("//source/bazel:package.py"), allow_single_file = True),
    "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
})

def package_release(name, static = None, shared = None, project = None, platforms = None, sources = None, **kwargs):
    """Package static and shared libraries with common source and headers.

    Called from the repository root to collect its source packages and build
    each supplied target for the selected SDK platforms. Binary archives end
    in -static.zip or -shared.zip. Static Windows archives use _static.lib so
    they can share an installation directory with the DLL's import library.
    Each archive preserves public definitions and the target's linkopts.
    Linkopts must remain valid outside the build tree; linker scripts and other
    additional linker inputs require their own distribution support. Dependency
    SDKs provide their own link requirements through the importer's deps.

    Args:
        name: Release packaging target name.
        static: Optional static_library target. Supply at least one variant.
        shared: Optional shared_library target. Supply at least one variant.
        project: Published name and EXPORTED identifier before uppercasing,
            defaulting to the module name. Match the library macros' project.
        platforms: Platform names to publish, defaulting to all SDK platforms.
        sources: Source archive inputs. Omit at the repository root to collect
            its standard source packages and build configuration.
        **kwargs: Common rule attributes such as visibility, tags and testonly.
    """
    if not static and not shared:
        fail("package_release requires a static or shared library")
    selected = _TARGETS.keys() if platforms == None else platforms
    if not selected or any([platform not in _TARGETS for platform in selected]):
        fail("platforms must select supported SDK platforms: " + str(_TARGETS.keys()))
    _package_release(
        name = name,
        static = static,
        shared = shared,
        project = project or native.module_name(),
        platforms = selected,
        version = native.module_version(),
        sources = sources if sources != None else native.glob(["source/**", "validation/**"], allow_empty = True) + ["//" + package + ":sources" for package in native.subpackages(include = ["source", "validation", "tests", "benchmarks"], allow_empty = True)] + ["BUILD", "MODULE.bazel", "LICENSE", ".bazelrc", ".bazelversion", ".clang-format"],
        **kwargs
    )

def source_files(name = "sources"):
    """Collect package sources and the sources targets of descendant packages.

    Args:
        name: Filegroup target name, defaulting to the release's sources label.
    """
    native.filegroup(
        name = name,
        srcs = native.glob(["**"], allow_empty = True) + ["//" + native.package_name() + "/" + package + ":sources" for package in native.subpackages(include = ["**"], allow_empty = True)],
        visibility = ["//visibility:public"],
    )
