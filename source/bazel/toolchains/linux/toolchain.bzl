# Copyright (c) 2023-present Matt Kaes and contributors

"""Native Clang configuration shared by the ecosystem's Linux builds.

The release CPU contract is x86-64-v3 with RDRAND. The SDK pins Ubuntu 22.04
headers and libraries from the September 25, 2026 snapshot, using glibc 2.35
and dynamic libstdc++. Platform implementations can select scalar algorithms
while preserving that published machine baseline.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "feature", "flag_group", "flag_set", "tool_path")
load("@host_tools//:settings.bzl", "AR", "COV", "CPP", "CXX", "ELF_LINKER", "HOST_SYSTEM", "NM", "OBJDUMP", "RESOURCE_INCLUDE", "STRIP")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")
load(":toolchains/reproducible.bzl", "COMPILE_FLAGS")
load(":toolchains/linux/repository.bzl", _GCC_DIRECTORY = "GCC_DIRECTORY")

_TARGET_TRIPLE = "x86_64-linux-gnu"

_COMPILE = [ACTION_NAMES.c_compile, ACTION_NAMES.cpp_compile]
_LINK = [ACTION_NAMES.cpp_link_executable, ACTION_NAMES.cpp_link_dynamic_library, ACTION_NAMES.cpp_link_nodeps_dynamic_library]

def _flags(name, actions, flags, enabled = True):
    """Apply one ordered flag list to a set of toolchain actions.

    Args:
        name: Feature name used by the C++ toolchain configuration.
        actions: Bazel action names that receive the flags.
        flags: Command line arguments in invocation order.
        enabled: Whether the feature is active by default.

    Returns:
        A toolchain feature containing the requested flag set.
    """
    return feature(name = name, enabled = enabled, flag_sets = [flag_set(actions = actions, flag_groups = [flag_group(flags = flags)])])

def _impl(ctx):
    """Configure Clang and LLD for the declared Linux target sysroot.

    Args:
        ctx: Analysis context of the compiler configuration rule.

    Returns:
        CcToolchainConfigInfo for the Linux x86_64 target.
    """
    sdk = Label("@linux_sdk//:files").workspace_root
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = [
            feature(name = "supports_pic", enabled = True),
            _flags("reproducible_compile", _COMPILE, COMPILE_FLAGS),
            _flags("target_sdk", _COMPILE + _LINK, ["--target=" + _TARGET_TRIPLE, "--sysroot=" + sdk, "--gcc-install-dir=" + sdk + "/" + _GCC_DIRECTORY]),
            feature(name = "pic", enabled = True, flag_sets = [flag_set(actions = _COMPILE, flag_groups = [flag_group(flags = ["-fPIC"], expand_if_available = "pic")])]),
            _flags("common_compile", _COMPILE, ["-Wall", "-Werror", "-Wmissing-declarations", "-fvisibility=hidden", "-fno-exceptions", "-fno-rtti", "-march=x86-64-v3", "-mrdrnd", "-no-canonical-prefixes", "-resource-dir", RESOURCE_INCLUDE.removesuffix("/include")]),
            _flags("cpp_language", [ACTION_NAMES.cpp_compile], ["-std=c++26", "-fvisibility-inlines-hidden"]),
            _flags("c_language", [ACTION_NAMES.c_compile], ["-xc", "-std=c23"]),
            _flags("opt", _COMPILE, ["-O3", "-DNDEBUG"], False),
            _flags("dbg", _COMPILE, ["-O0", "-g"], False),
            _flags("default_linker_flags", _LINK, ["-lstdc++", "-fuse-ld=lld"]),
        ],
        tool_paths = [tool_path(name = name, path = path) for name, path in [
            ("gcc", CXX),
            ("ld", ELF_LINKER),
            ("ar", AR),
            ("cpp", CPP),
            ("gcov", COV),
            ("nm", NM),
            ("objdump", OBJDUMP),
            ("strip", STRIP),
        ]],
        cxx_builtin_include_directories = [RESOURCE_INCLUDE, sdk],
        toolchain_identifier = "clang-linux-x86_64",
        host_system_name = HOST_SYSTEM,
        target_system_name = "linux",
        target_cpu = "x86_64",
        target_libc = "glibc",
        compiler = "clang",
        abi_version = "system-v",
        abi_libc_version = "glibc",
    )

cc_toolchain_config = rule(implementation = _impl, attrs = {}, provides = [CcToolchainConfigInfo])

# These labels form the Linux portion of Toolchain's root registration surface.
# buildifier: disable=unnamed-macro
def linux_targets():
    """Declare the Linux SDK files, compiler, platform and selection key."""
    cc_toolchain_config(name = "linux_x86_64_toolchain_config", tags = ["manual"])

    cc_toolchain(
        name = "linux_x86_64_toolchain",
        all_files = ":linux_files",
        compiler_files = ":linux_compiler_files",
        dwp_files = "@host_tools//:files",
        linker_files = ":linux_linker_files",
        objcopy_files = "@host_tools//:files",
        strip_files = "@host_tools//:files",
        supports_param_files = 0,
        toolchain_config = ":linux_x86_64_toolchain_config",
        toolchain_identifier = "linux_x86_64-toolchain",
        tags = ["manual"],
    )

    native.filegroup(name = "linux_compiler_files", srcs = ["@host_tools//:files", "@linux_sdk//:compiler"], tags = ["manual"])
    native.filegroup(name = "linux_linker_files", srcs = ["@host_tools//:files", "@linux_sdk//:linker"], tags = ["manual"])
    native.filegroup(name = "linux_files", srcs = [":linux_compiler_files", ":linux_linker_files"], tags = ["manual"])

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

    native.config_setting(
        name = "linux",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    )
