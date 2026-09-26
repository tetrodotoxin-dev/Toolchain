# Copyright (c) 2023-present Matt Kaes and contributors

"""Use an installed Microsoft SDK with the host's Clang and LLD.

xwin can prepare the SDK in winsysroot layout on Linux. Acquisition is explicit:
set TETRO_WINDOWS_SDK to that directory. Nothing here downloads another compiler
or accepts a software license during an ordinary project build.
"""

load("@rules_cc//cc/private/toolchain:windows_cc_toolchain_config.bzl", windows_config = "cc_toolchain_config")

def _sdk(ctx):
    source = ctx.os.environ.get("TETRO_WINDOWS_SDK")
    if not source:
        fail("Set --repo_env=TETRO_WINDOWS_SDK to a Microsoft SDK in xwin --use-winsysroot-style layout")
    root = ctx.path(source)
    crt = sorted((root.get_child("VC/Tools/MSVC")).readdir())[-1]
    sdk = root.get_child("Windows Kits/10")
    version = sorted(sdk.get_child("Include").readdir())[-1].basename
    ctx.symlink(crt.get_child("include"), "include/crt")
    ctx.symlink(crt.get_child("lib/x64"), "lib/crt")
    for part in ["ucrt", "shared", "um", "winrt"]:
        ctx.symlink(sdk.get_child("Include/" + version + "/" + part), "include/" + part)
    for part in ["ucrt", "um"]:
        ctx.symlink(sdk.get_child("Lib/" + version + "/" + part + "/x64"), "lib/" + part)
    ctx.file("BUILD.bazel", 'filegroup(name = "files", srcs = glob(["include/**", "lib/**"]), visibility = ["//visibility:public"])')

windows_sdk = repository_rule(implementation = _sdk, environ = ["TETRO_WINDOWS_SDK"], local = True)

def windows_toolchain_config():
    windows_config(
        name = "windows_config",
        abi_version = "msvc",
        all_compile_flags = [
            "/clang:-mavx2",
            "/clang:-mrdrnd",
            "/clang:-march=x86-64-v3",
            "/DPERI_WINDOWS",
            "/DNOMINMAX",
            "/D_CRT_SECURE_NO_WARNINGS",
            "/clang:-fno-exceptions",
            "/clang:-fno-rtti",
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
            "/usr/lib/clang/22/include",
            Label("@windows_sdk//:files").workspace_root + "/include",
        ],
        cxx_flags = ["/std:c++latest"],
        default_link_flags = ["/DEBUG:FULL"] + ["/LIBPATH:" + Label("@windows_sdk//:files").workspace_root + "/lib/" + part for part in [
            "crt",
            "ucrt",
            "um",
        ]],
        host_system_name = "linux",
        msvc_cl_path = "/usr/bin/clang-cl",
        msvc_env_include = Label("@windows_sdk//:files").workspace_root + "/include/crt",
        msvc_env_lib = Label("@windows_sdk//:files").workspace_root + "/lib/crt",
        msvc_env_path = "/usr/bin:/bin",
        msvc_env_tmp = "/tmp",
        msvc_lib_path = "archive.sh",
        msvc_link_path = "/usr/bin/lld-link",
        msvc_ml_path = "/usr/bin/clang-cl",
        target_libc = "ucrt",
        target_system_name = "windows",
        toolchain_identifier = "clang-windows-x64",
        win32_winnt_flag = "/D_WIN32_WINNT=0x0A00",
    )
