# Copyright (c) 2023-present Matt Kaes and contributors

"""Configure clang-cl against the selected MSVC headers and libraries."""

load("@host_tools//:settings.bzl", "ARCHIVER", "CLANG", "HOST_SYSTEM", "LINKER", "PATH", "RESOURCE_INCLUDE", "TEMP")

# Pinned rules_cc 0.2.17 provides its MSVC configuration at this private path.
# Reusing it keeps the Windows action grammar and import library handling in
# the upstream implementation. Recheck this path when upgrading rules_cc.
# buildifier: disable=bzl-visibility
load("@rules_cc//cc/private/toolchain:windows_cc_toolchain_config.bzl", windows_config = "cc_toolchain_config")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load(":toolchains/reproducible.bzl", "COMPILE_FLAGS")

def _host_tool(path):
    """Resolve a host executable from the execution root without embedding it."""
    package_root = Label("//:windows").workspace_root
    prefix = "../" * len(package_root.split("/")) if package_root else ""
    return prefix + Label("@host_tools//:files").workspace_root + "/" + path

def windows_toolchain_config():
    """Declare the windows_config target using clang-cl and the Windows SDK."""
    windows_config(
        name = "windows_config",
        tags = ["manual"],
        abi_version = "msvc",
        all_compile_flags = [
            "/Brepro",
            "/X",
            "/clang:-gno-codeview-command-line",
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
        ] + ["/clang:" + flag for flag in COMPILE_FLAGS] + ["/imsvc" + RESOURCE_INCLUDE] + ["/imsvc" + Label("@windows_sdk//:files").workspace_root + "/include/" + part for part in [
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
        dbg_mode_debug_flag = "/DEBUG:FULL",
        fastbuild_mode_debug_flag = "/DEBUG:FULL",
        default_link_flags = ["/timestamp:0", "/pdbaltpath:%%_PDB%%", "/pdbsourcepath:.", "/lldignoreenv", "/vfsoverlay:" + Label("@windows_sdk//:files").workspace_root + "/case.yaml"] + ["/LIBPATH:" + Label("@windows_sdk//:files").workspace_root + "/lib/" + part for part in [
            "crt",
            "ucrt",
            "um",
        ]],
        host_system_name = HOST_SYSTEM,
        msvc_cl_path = _host_tool("llvm/bin/" + CLANG.split("/")[-1]),
        msvc_env_include = Label("@windows_sdk//:files").workspace_root + "/include/crt",
        msvc_env_lib = Label("@windows_sdk//:files").workspace_root + "/lib/crt",
        msvc_env_path = PATH,
        msvc_env_tmp = TEMP,
        msvc_lib_path = _host_tool(("llvm/bin/" if "/llvm/bin/" in ARCHIVER else "") + ARCHIVER.split("/")[-1]),
        msvc_link_path = _host_tool("llvm/bin/" + LINKER.split("/")[-1]),
        msvc_ml_path = _host_tool("llvm/bin/" + CLANG.split("/")[-1]),
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
        tags = ["manual"],
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
        tags = ["manual"],
        srcs = [
            "@host_tools//:files",
            "@windows_sdk//:files",
        ],
    )
