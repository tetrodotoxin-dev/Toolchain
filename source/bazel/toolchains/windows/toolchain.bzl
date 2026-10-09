# Copyright (c) 2023-present Matt Kaes and contributors

"""Supply the MSVC headers and libraries used with the selected LLVM tools.

Pinned Microsoft archives are extracted only when a Windows target is requested.
TETRO_WINDOWS_SDK selects an existing SDK in winsysroot layout when a developer
wants to use an installed version instead.
"""

load("@host_tools//:settings.bzl", "ARCHIVER", "CLANG", "HOST_SYSTEM", "LINKER", "PATH", "PYTHON", "RESOURCE_INCLUDE", "TEMP")

# Pinned rules_cc 0.2.17 provides its MSVC configuration at this private path.
# Reusing it keeps the Windows action grammar and import library handling in
# the upstream implementation. Recheck this path when upgrading rules_cc.
# buildifier: disable=bzl-visibility
load("@rules_cc//cc/private/toolchain:windows_cc_toolchain_config.bzl", windows_config = "cc_toolchain_config")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")

def _sdk(ctx):
    """Assemble MSVC and Windows SDK files from downloads or an installed SDK.

    Args:
        ctx: Repository context with package pins, normalization tools and
            the optional installed-SDK selection.
    """
    source = ctx.os.environ.get("TETRO_WINDOWS_SDK")
    if source:
        # An explicit installed SDK remains useful when testing a newer vendor
        # release. The default path below always uses the pinned packages.
        root = ctx.path(source)
        crt = sorted(root.get_child("VC/Tools/MSVC").readdir())[-1]
        sdk = root.get_child("Windows Kits/10")
        version = sorted(sdk.get_child("Include").readdir())[-1].basename
        ctx.symlink(crt.get_child("include"), "include/crt")
        for name, path in {path.basename.lower(): path for path in crt.get_child("lib/x64").readdir()}.items():
            ctx.symlink(path, "lib/crt/" + name)
        for part in ["ucrt", "shared", "um", "winrt"]:
            ctx.symlink(sdk.get_child("Include/" + version + "/" + part), "include/" + part)
        for part in ["ucrt", "um"]:
            for name, path in {path.basename.lower(): path for path in sdk.get_child("Lib/" + version + "/" + part + "/x64").readdir()}.items():
                ctx.symlink(path, "lib/" + part + "/" + name)
    else:
        for index, package in enumerate(json.decode(ctx.read(ctx.attr._packages))):
            archive = "archives/" + str(index) + ".zip"
            ctx.download(url = package["url"], sha256 = package["sha256"], output = archive)
            for prefix, output in package["trees"].items():
                ctx.extract(archive, output = output, strip_prefix = prefix)
            ctx.delete(archive)
    ctx.file("normalize.py", ctx.read(ctx.attr._normalize))
    normalized = ctx.execute([PYTHON, ctx.path("normalize.py"), "windows", "external/" + ctx.name])
    if normalized.return_code:
        fail(normalized.stderr)

    # Runtime DLLs support local validation as development inputs. Product SDK
    # archives select runtime libraries from their declared dependency graph.
    ctx.template("BUILD.bazel", ctx.attr._build)

windows_sdk = repository_rule(implementation = _sdk, attrs = {
    "_build": attr.label(default = Label("//source/bazel:toolchains/windows/sdk.BUILD.tpl")),
    "_packages": attr.label(default = Label("//source:sdk/windows.json")),
    "_normalize": attr.label(default = Label("//source:sdk/normalize.py")),
}, environ = ["TETRO_WINDOWS_SDK"])

def windows_toolchain_config():
    """Declare the windows_config target using clang-cl and the Windows SDK."""
    windows_config(
        name = "windows_config",
        abi_version = "msvc",
        all_compile_flags = [
            "/clang:-resource-dir=" + RESOURCE_INCLUDE.removesuffix("/include"),
            "/clang:-ivfsoverlay",
            "/clang:" + Label("@windows_sdk//:files").workspace_root + "/case.yaml",
            "/clang:-mavx2",
            "/clang:-mrdrnd",
            "/clang:-march=x86-64-v3",
            "/DNOMINMAX",
            "/D_CRT_SECURE_NO_WARNINGS",
            "/clang:-fno-exceptions",
            "/clang:-fno-rtti",
            "/clang:-Werror=missing-declarations",
        ] + ["/imsvc" + Label("@windows_sdk//:files").workspace_root + "/include/" + part for part in [
            "crt",
            "ucrt",
            "shared",
            "um",
            "winrt",
        ]],
        archiver_flags = [],
        compiler = "clang-cl",
        conly_flags = ["/clang:-std=c23"],
        cpu = "x64_windows",
        cxx_builtin_include_directories = [
            RESOURCE_INCLUDE,
            Label("@windows_sdk//:files").workspace_root + "/include",
        ],
        cxx_flags = ["/std:c++latest"],
        default_link_flags = ["/DEBUG:FULL", "/vfsoverlay:" + Label("@windows_sdk//:files").workspace_root + "/case.yaml"] + ["/LIBPATH:" + Label("@windows_sdk//:files").workspace_root + "/lib/" + part for part in [
            "crt",
            "ucrt",
            "um",
        ]],
        host_system_name = HOST_SYSTEM,
        msvc_cl_path = CLANG,
        msvc_env_include = Label("@windows_sdk//:files").workspace_root + "/include/crt",
        msvc_env_lib = Label("@windows_sdk//:files").workspace_root + "/lib/crt",
        msvc_env_path = PATH,
        msvc_env_tmp = TEMP,
        msvc_lib_path = ARCHIVER,
        msvc_link_path = LINKER,
        msvc_ml_path = CLANG,
        target_libc = "ucrt",
        target_system_name = "windows",
        toolchain_identifier = "clang-windows-x64",
        win32_winnt_flag = "/D_WIN32_WINNT=0x0A00",
    )

# These labels form the Windows portion of Toolchain's root registration
# surface. The empty group satisfies auxiliary action slots in the MSVC rule.
# buildifier: disable=unnamed-macro
def windows_targets():
    """Declare the Windows SDK files, compiler, platform and selection key."""
    native.config_setting(
        name = "windows",
        constraint_values = [
            "@platforms//os:windows",
            "@platforms//cpu:x86_64",
        ],
    )

    native.platform(
        name = "windows_x64",
        constraint_values = [
            "@platforms//os:windows",
            "@platforms//cpu:x86_64",
        ],
    )

    # Upstream rules own the MSVC command grammar, dependency tracking and
    # import-library flags. This configuration supplies our compiler options
    # and SDK locations to that grammar.
    windows_toolchain_config()
    native.filegroup(name = "windows_empty")

    cc_toolchain(
        name = "windows_toolchain",
        all_files = ":windows_files",
        ar_files = ":windows_files",
        as_files = ":windows_empty",
        compiler_files = ":windows_files",
        dwp_files = ":windows_empty",
        linker_files = ":windows_files",
        objcopy_files = ":windows_empty",
        strip_files = ":windows_empty",
        supports_param_files = 1,
        toolchain_config = ":windows_config",
    )

    native.toolchain(
        name = "cc_toolchain_for_windows_x64",
        exec_compatible_with = [
            "@platforms//os:" + HOST_SYSTEM,
            "@platforms//cpu:x86_64",
        ],
        target_compatible_with = [
            "@platforms//os:windows",
            "@platforms//cpu:x86_64",
        ],
        toolchain = ":windows_toolchain",
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    native.filegroup(
        name = "windows_files",
        srcs = [
            "@host_tools//:files",
            "@windows_sdk//:files",
        ],
    )
