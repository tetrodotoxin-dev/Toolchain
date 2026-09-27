# Copyright (c) 2023-present Matt Kaes and contributors

"""Register the compiler targets and package Toolchain's source distribution."""

load("@host_tools//:settings.bzl", "HOST_SYSTEM")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")
load("//:linux.bzl", "cc_toolchain_config")
load("//:wasm.bzl", "wasm_cc_toolchain_config")
load("//:windows.bzl", "windows_toolchain_config")

def toolchains():
    native.filegroup(name = "empty")

    cc_toolchain_config(name = "linux_x86_64_toolchain_config")

    cc_toolchain(
        name = "linux_x86_64_toolchain",
        all_files = ":linux_files",
        compiler_files = ":linux_files",
        dwp_files = "@host_tools//:files",
        linker_files = ":linux_files",
        objcopy_files = "@host_tools//:files",
        strip_files = "@host_tools//:files",
        supports_param_files = 0,
        toolchain_config = ":linux_x86_64_toolchain_config",
        toolchain_identifier = "linux_x86_64-toolchain",
    )

    native.filegroup(name = "linux_files", srcs = ["@host_tools//:files", "@linux_sdk//:files"])

    native.toolchain(
        name = "cc_toolchain_for_linux_x86_64",
        exec_compatible_with = [
            "@platforms//cpu:x86_64",
            "@platforms//os:" + HOST_SYSTEM,
        ],
        target_compatible_with = [
            "@platforms//cpu:x86_64",
            "@platforms//os:linux",
        ],
        toolchain = ":linux_x86_64_toolchain",
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    native.platform(
        name = "linux_x86_64",
        constraint_values = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    )

    native.platform(
        name = "wasm32",
        constraint_values = [
            "@platforms//cpu:wasm32",
            "@platforms//os:emscripten",
        ],
    )

    wasm_cc_toolchain_config(
        name = "wasm32_config",
        headers = "@emscripten_sysroot//:headers",
    )

    cc_toolchain(
        name = "wasm32_toolchain",
        all_files = ":wasm_files",
        ar_files = "@host_tools//:files",
        as_files = "@host_tools//:files",
        compiler_files = ":wasm_files",
        dwp_files = "@host_tools//:files",
        linker_files = "@host_tools//:files",
        objcopy_files = "@host_tools//:files",
        strip_files = "@host_tools//:files",
        supports_param_files = 1,
        toolchain_config = ":wasm32_config",
        toolchain_identifier = "clang-wasm32",
    )

    native.filegroup(name = "wasm_files", srcs = ["@host_tools//:files", "@emscripten_sysroot//:headers"])

    native.toolchain(
        name = "cc_toolchain_for_wasm32",
        exec_compatible_with = [
            "@platforms//os:" + HOST_SYSTEM,
            "@platforms//cpu:x86_64",
        ],
        target_compatible_with = [
            "@platforms//cpu:wasm32",
            "@platforms//os:emscripten",
        ],
        toolchain = ":wasm32_toolchain",
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    native.config_setting(
        name = "linux",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    )

    native.config_setting(
        name = "web",
        constraint_values = [
            "@platforms//os:emscripten",
            "@platforms//cpu:wasm32",
        ],
    )

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

    native.exports_files([
        "exports.py",
        "package.bzl",
        "library.bzl",
        "sdk.bzl",
    ])

    # Upstream rules own the MSVC command grammar, dependency tracking and import
    # library flags. Only our compiler options and SDK locations are specified here.
    windows_toolchain_config()

    cc_toolchain(
        name = "windows_toolchain",
        all_files = ":windows_files",
        ar_files = ":windows_files",
        as_files = ":empty",
        compiler_files = ":windows_files",
        dwp_files = ":empty",
        linker_files = ":windows_files",
        objcopy_files = ":empty",
        strip_files = ":empty",
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

    pkg_tar(
        name = "sdk",
        srcs = [":sources"],
        package_file_name = native.module_name() + "-" + native.module_version() + "-source.tar.gz",
        extension = "tar.gz",
        mode = "0644",
        strip_prefix = ".",
        stamp = 0,
    )
