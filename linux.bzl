# Copyright (c) 2023-present Matt Kaes and contributors

"""Native Clang configuration shared by the ecosystem's Linux builds.

The release CPU contract is x86-64-v3 with RDRAND. Platform implementations can
select scalar algorithms without changing that published machine baseline.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "feature", "flag_group", "flag_set", "tool_path")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")

_COMPILE = [ACTION_NAMES.c_compile, ACTION_NAMES.cpp_compile]
_LINK = [ACTION_NAMES.cpp_link_executable, ACTION_NAMES.cpp_link_dynamic_library, ACTION_NAMES.cpp_link_nodeps_dynamic_library]

def _flags(name, actions, flags, enabled = True):
    return feature(name = name, enabled = enabled, flag_sets = [flag_set(actions = actions, flag_groups = [flag_group(flags = flags)])])

def _impl(ctx):
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = [
            feature(name = "supports_pic", enabled = True),
            feature(name = "pic", enabled = True, flag_sets = [flag_set(actions = _COMPILE, flag_groups = [flag_group(flags = ["-fPIC"], expand_if_available = "pic")])]),
            _flags("common_compile", _COMPILE, ["-Wall", "-Werror", "-fno-exceptions", "-fno-rtti", "-march=x86-64-v3", "-mrdrnd", "-no-canonical-prefixes"]),
            _flags("cpp_language", [ACTION_NAMES.cpp_compile], ["-std=c++26"]),
            _flags("c_language", [ACTION_NAMES.c_compile], ["-xc", "-std=c23"]),
            _flags("opt", _COMPILE, ["-O3", "-DNDEBUG"], False),
            _flags("dbg", _COMPILE, ["-O0", "-g"], False),
            _flags("default_linker_flags", _LINK, ["-lstdc++", "-fuse-ld=lld"]),
        ],
        tool_paths = [tool_path(name = name, path = path) for name, path in [
            ("gcc", "/usr/bin/clang++"),
            ("ld", "/usr/bin/ld.lld"),
            ("ar", "/usr/bin/ar"),
            ("cpp", "/usr/bin/clang-cpp"),
            ("gcov", "/bin/false"),
            ("nm", "/usr/bin/nm"),
            ("objdump", "/usr/bin/objdump"),
            ("strip", "/usr/bin/strip"),
        ]],
        cxx_builtin_include_directories = ["/usr/lib/clang", "/usr/include"],
        toolchain_identifier = "clang-linux-x86_64",
        host_system_name = "linux",
        target_system_name = "linux",
        target_cpu = "x86_64",
        target_libc = "glibc",
        compiler = "clang",
        abi_version = "system-v",
        abi_libc_version = "glibc",
    )

cc_toolchain_config = rule(implementation = _impl, attrs = {}, provides = [CcToolchainConfigInfo])
