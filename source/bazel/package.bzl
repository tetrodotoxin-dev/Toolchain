# Copyright (c) 2023-present Matt Kaes and contributors

"""Package one project's source, headers and every target's linker outputs."""

load("@host_tools//:settings.bzl", "PYTHON")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_TARGETS = {
    "linux-x86_64-v3": str(Label("//:linux_x86_64")),
    "windows-x86_64-msvc": str(Label("//:windows_x64")),
    "wasm32-emscripten": str(Label("//:wasm32")),
}

# Bazel supplies both arguments to every transition callback. Release builds
# select fixed platforms and optimization settings independently of either one.
# buildifier: disable=unused-variable
def _targets(settings, attr):
    """Select an optimized build for each SDK platform.

    Args:
        settings: Incoming build settings, unused by this fixed platform list.
        attr: Packaging rule attributes, unused by this transition.

    Returns:
        A dictionary mapping SDK platform names to their build settings.
    """
    return {name: {
        "//command_line_option:platforms": [platform],
        "//command_line_option:compilation_mode": "opt",
    } for name, platform in _TARGETS.items()}

_transition = transition(
    implementation = _targets,
    inputs = [],
    outputs = ["//command_line_option:platforms", "//command_line_option:compilation_mode"],
)

def _binaries(target, project):
    """Select the target's link outputs and their release archive names.

    Args:
        target: Configured library target for one SDK platform.
        project: Published library name used for static archive filenames.

    Returns:
        A dictionary from output Files to archive basenames, preferring a
        static library when available and otherwise selecting shared outputs.
    """
    files = {}
    if CcInfo in target:
        for entry in target[CcInfo].linking_context.linker_inputs.to_list():
            if entry.owner != target.label:
                continue
            for library in entry.libraries:
                # PIC archives can also be linked into a consumer's plugin.
                archive = library.pic_static_library or library.static_library
                binary = archive or library.resolved_symlink_dynamic_library or library.dynamic_library
                if binary:
                    files[binary] = (project + ".lib" if binary.extension == "lib" else "lib" + project + ".a") if archive else binary.basename
                interface = library.resolved_symlink_interface_library or library.interface_library
                if interface and not archive:
                    files[interface] = binary.basename.removesuffix(".dll") + ".lib"
    return files or {file: file.basename for file in target[DefaultInfo].files.to_list()}

def _headers(target):
    """Collect repository headers with the include paths consumers use.

    Args:
        target: Configured target providing the C++ compilation context.

    Returns:
        A list of [File, include_path] pairs from the target's repository.
    """
    if CcInfo not in target:
        return []
    context = target[CcInfo].compilation_context
    roots = context.includes.to_list() + context.system_includes.to_list()
    headers = []
    for file in context.headers.to_list():
        if file.owner.workspace_root != target.label.workspace_root:
            continue
        prefixes = [root + "/" for root in roots if file.path.startswith(root + "/")]
        if prefixes:
            prefix = sorted(prefixes, key = len)[-1]
            headers.append([file, file.path[len(prefix):]])
    return headers

def _package(ctx):
    """Write source, header and platform archives with a checksum manifest.

    Args:
        ctx: Rule context with source files and the target split by platform.

    Returns:
        A list containing DefaultInfo for the archives and checksum file.
    """
    stem = ctx.attr.project + "-" + ctx.attr.version
    headers = _headers(ctx.split_attr.target["linux-x86_64-v3"])
    license = [[file.path, "LICENSE"] for file in ctx.files.sources if file.short_path == "LICENSE"]
    archives = {
        stem + "-headers.zip": [[file.path, "include/" + path] for file, path in headers] + license,
        stem + "-source.zip": [[file.path, file.short_path] for file in ctx.files.sources],
    }
    inputs = [file for file, path in headers] + ctx.files.sources
    for platform, target in ctx.split_attr.target.items():
        files = _binaries(target, ctx.attr.project)
        if not files:
            fail("Release target produced no binaries: " + str(target.label))
        archives[stem + "-" + platform + ".zip"] = [[file.path, "lib/" + name] for file, name in files.items()] + license
        inputs.extend(files.keys())
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
    "target": attr.label(mandatory = True, cfg = _transition),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "sources": attr.label_list(allow_files = True),
    "_writer": attr.label(default = Label("//source/bazel:package.py"), allow_single_file = True),
    "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
})

def package_release(name, target):
    """Package a library using the current module's project name and version.

    Called from the repository root to collect its source packages and build
    the target for each supported SDK platform.

    Args:
        name: Release packaging target name.
        target: Library target whose headers and binaries enter the archives.
    """
    _package_release(
        name = name,
        target = target,
        project = native.module_name(),
        version = native.module_version(),
        sources = native.glob(["source/**", "validation/**"], allow_empty = True) + ["//" + package + ":sources" for package in native.subpackages(include = ["source", "validation", "tests", "benchmarks"], allow_empty = True)] + ["BUILD", "MODULE.bazel", "LICENSE", ".bazelrc", ".bazelversion", ".clang-format"],
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
