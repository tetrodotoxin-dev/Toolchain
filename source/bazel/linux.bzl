# Copyright (c) 2023-present Matt Kaes and contributors

"""Native Clang configuration shared by the ecosystem's Linux builds.

The release CPU contract is x86-64-v3 with RDRAND. The SDK pins Ubuntu 22.04
headers and libraries from the September 25, 2026 snapshot, using glibc 2.35
and dynamic libstdc++. Platform implementations can select scalar algorithms
without changing that published machine baseline.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "feature", "flag_group", "flag_set", "tool_path")
load("@host_tools//:settings.bzl", "AR", "COV", "CPP", "CXX", "ELF_LINKER", "HOST_SYSTEM", "NM", "OBJDUMP", "PYTHON", "RESOURCE_INCLUDE", "STRIP")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")
load(":sdk.bzl", "extract_debian")

# A fixed target sysroot keeps releases independent of the build machine's
# distribution. Ubuntu 22.04 supplies the existing glibc and libstdc++ model.
# The dated snapshot keeps every package available under its reviewed checksum.
def _sdk(ctx):
    """Assemble the Linux sysroot from pinned Debian packages.

    Args:
        ctx: Repository context with package pins and the sysroot normalizer.
    """
    packages = json.decode(ctx.read(ctx.attr._packages))
    extract_debian(ctx, {
        "https://snapshot.ubuntu.com/ubuntu/20260925T000000Z/" + package["path"]: package["sha256"]
        for package in packages.values()
    })
    ctx.file("normalize.py", ctx.read(ctx.attr._normalize))
    normalized = ctx.execute([PYTHON, ctx.path("normalize.py"), "linux"])
    if normalized.return_code:
        fail(normalized.stderr)
    ctx.file("BUILD.bazel", 'filegroup(name = "files", srcs = glob(["usr/include/**", "usr/lib/**", "lib/**", "lib64/**"], allow_empty = True), visibility = ["//visibility:public"])')

linux_sdk = repository_rule(implementation = _sdk, attrs = {
    "_packages": attr.label(default = Label("//source:sdk/linux.json")),
    "_normalize": attr.label(default = Label("//source:sdk/normalize.py")),
})

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
            _flags("target_sdk", _COMPILE + _LINK, ["--target=x86_64-linux-gnu", "--sysroot=" + sdk, "--gcc-install-dir=" + sdk + "/usr/lib/gcc/x86_64-linux-gnu/11"]),
            feature(name = "pic", enabled = True, flag_sets = [flag_set(actions = _COMPILE, flag_groups = [flag_group(flags = ["-fPIC"], expand_if_available = "pic")])]),
            _flags("common_compile", _COMPILE, ["-Wall", "-Werror", "-fvisibility=hidden", "-fno-exceptions", "-fno-rtti", "-march=x86-64-v3", "-mrdrnd", "-no-canonical-prefixes", "-resource-dir", RESOURCE_INCLUDE.removesuffix("/include")]),
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
