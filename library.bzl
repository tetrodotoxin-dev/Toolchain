# Copyright (c) 2023-present Matt Kaes and contributors

"""Build one shared library and package the same artifacts consumers link.

The implementation target is available to the project's validation package
when it must instrument code before linking. Ordinary consumers import the
shared library, keeping allocator and process state in their one runtime.
"""

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":package.bzl", "sdk_release")

LINUX = Label("//:linux")
WEB = Label("//:web")
WINDOWS = Label("//:windows")
PLATFORMS = {LINUX: "linux-x86_64-v3", WEB: "wasm32-emscripten", WINDOWS: "windows-x86_64-msvc"}
PERIMORTEM_DEFINES = select({LINUX: ["PERI_LINUX"], WEB: ["PERI_WASM"], WINDOWS: ["PERI_WINDOWS"]})

# Bazel's automatic DEF parser is a Windows executable. Cross builds inspect
# the same owned COFF objects with the host tools and supply the resulting DEF.
def _exports(ctx):
    objects = []
    for entry in ctx.attr.library[CcInfo].linking_context.linker_inputs.to_list():
        for library in entry.libraries:
            objects.extend(library.pic_objects or library.objects or [])
    output = ctx.actions.declare_file(ctx.label.name + ".def")
    ctx.actions.run_shell(
        inputs = depset(objects + [ctx.file._writer]),
        outputs = [output],
        command = 'python3 "$@"',
        arguments = [ctx.file._writer.path, output.path] + [f.path for f in objects],
        mnemonic = "WindowsExports",
    )
    return [DefaultInfo(files = depset([output]))]

_exports_rule = rule(implementation = _exports, attrs = {
    "library": attr.label(providers = [CcInfo]),
    "_writer": attr.label(default = Label("//:exports.py"), allow_single_file = True),
})

def shared_library(name, srcs, hdrs, deps = [], defines = [], local_defines = [], linkopts = [], platforms = PLATFORMS, copts = []):
    native.filegroup(name = "public_headers", srcs = hdrs)
    cc_library(name = "headers", hdrs = hdrs, include_prefix = name, defines = defines, deps = deps)
    cc_library(
        name = "implementation",
        srcs = srcs,
        deps = [":headers"],
        local_defines = local_defines,
        copts = copts,
        visibility = ["//validation:__subpackages__"],
    )
    _exports_rule(name = "exports", library = ":implementation", visibility = ["//visibility:private"])
    cc_shared_library(
        name = "build",
        tags = ["__DONT_DEPEND_ON_DEF_PARSER__"],
        win_def_file = select({WINDOWS: ":exports", "//conditions:default": None}),
        deps = [":implementation"],
        shared_lib_name = select({WINDOWS: name + ".dll", LINUX: "lib" + name + ".so", WEB: "lib" + name + ".so"}),
        user_link_flags = select({LINUX: ["-Wl,-z,defs", "-Wl,-soname,lib" + name + ".so", "-Wl,-rpath,$ORIGIN"], "//conditions:default": []}) + linkopts,
    )
    native.filegroup(name = "interface", srcs = [":build"], output_group = "interface_library")
    cc_import(
        name = name,
        shared_library = ":build",
        interface_library = select({WINDOWS: ":interface", "//conditions:default": None}),
        deps = [":headers"],
    )
    sdk_release(name = "sdk", files = {":public_headers": "include/" + name + "/", ":build": "lib/", "LICENSE": "LICENSE"}, platforms = platforms, platform_files = {WINDOWS: {":interface": "lib/" + name + ".lib"}})
