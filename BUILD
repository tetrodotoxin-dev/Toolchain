# # Tetrodotoxin
# Copyright (c) 2023-present Matt Kaes and contributors

"Shared Clang targets and release assets for Linux, Wasm and Windows."

load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load(":linux.bzl", "cc_toolchain_config")
load(":package.bzl", "sdk_release")
load(":wasm.bzl", "wasm_cc_toolchain_config")
load(":windows.bzl", "windows_toolchain_config")

package(default_visibility = ["//visibility:public"])

filegroup(name = "empty")

cc_toolchain_config(name = "linux_x86_64_toolchain_config")

cc_toolchain(
    name = "linux_x86_64_toolchain",
    all_files = ":empty",
    compiler_files = ":empty",
    dwp_files = ":empty",
    linker_files = ":empty",
    objcopy_files = ":empty",
    strip_files = ":empty",
    supports_param_files = 0,
    toolchain_config = ":linux_x86_64_toolchain_config",
    toolchain_identifier = "linux_x86_64-toolchain",
)

toolchain(
    name = "cc_toolchain_for_linux_x86_64",
    exec_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    toolchain = ":linux_x86_64_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

platform(
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
    all_files = "@emscripten_sysroot//:headers",
    ar_files = ":empty",
    as_files = ":empty",
    compiler_files = "@emscripten_sysroot//:headers",
    dwp_files = ":empty",
    linker_files = ":empty",
    objcopy_files = ":empty",
    strip_files = ":empty",
    supports_param_files = 1,
    toolchain_config = ":wasm32_config",
    toolchain_identifier = "clang-wasm32",
)

toolchain(
    name = "cc_toolchain_for_wasm32",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//cpu:wasm32",
        "@platforms//os:emscripten",
    ],
    toolchain = ":wasm32_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

config_setting(
    name = "linux",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

config_setting(
    name = "web",
    constraint_values = [
        "@platforms//os:emscripten",
        "@platforms//cpu:wasm32",
    ],
)

config_setting(
    name = "windows",
    constraint_values = [
        "@platforms//os:windows",
        "@platforms//cpu:x86_64",
    ],
)

platform(
    name = "windows_x64",
    constraint_values = [
        "@platforms//os:windows",
        "@platforms//cpu:x86_64",
    ],
)

exports_files([
    "archive.sh",
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
    compiler_files = "@windows_sdk//:files",
    dwp_files = ":empty",
    linker_files = "@windows_sdk//:files",
    objcopy_files = ":empty",
    strip_files = ":empty",
    supports_param_files = 1,
    toolchain_config = ":windows_config",
)

toolchain(
    name = "cc_toolchain_for_windows_x64",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:x86_64",
    ],
    toolchain = ":windows_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

filegroup(
    name = "windows_files",
    srcs = [
        "archive.sh",
        "@windows_sdk//:files",
    ],
)

# Consumers can pin this source archive just as they pin binary SDK releases.
filegroup(
    name = "sources",
    srcs = glob([
        "*.bzl",
        "*.py",
        "*.sh",
    ]) + [
        "BUILD",
        "LICENSE",
        "MODULE.bazel",
        "test_support.BUILD.bazel",
    ],
)

sdk_release(
    name = "sdk",
    files = {":sources": "/"},
    modes = {"archive.sh": "0755"},
    platforms = {"//conditions:default": "source"},
)
