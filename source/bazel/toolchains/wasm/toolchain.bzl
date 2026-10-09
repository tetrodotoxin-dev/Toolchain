# Copyright (c) 2023-present Matt Kaes and contributors

"""Clang code generation for modules hosted by an Emscripten application."""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "feature", "flag_group", "flag_set", "tool_path")
load("@host_tools//:settings.bzl", "AR", "COV", "CPP", "CXX", "HOST_SYSTEM", "NM", "OBJDUMP", "RESOURCE_INCLUDE", "STRIP", "WASM_LINKER")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")

def _sysroot(ctx):
    """Extract the pinned Emscripten headers into a Bazel repository.

    Args:
        ctx: Repository context used to download and expose the headers.
    """

    # The sysroot archive contributes target headers. The selected LLVM
    # distribution contributes the compiler, linker and resource headers.
    ctx.download_and_extract(
        url = "https://storage.googleapis.com/webassembly/emscripten-releases-builds/linux/c387d7a7e9537d0041d2c3ae71b7538cc978104e/wasm-binaries.tar.xz",
        sha256 = "a06e7ddda0c168f7ad52e6e0509c98db3545dcb254d3b9052e9e6b8423eaee7d",
        strip_prefix = "install/emscripten/cache/sysroot/include",
    )
    ctx.template("BUILD", ctx.attr._build)

emscripten_sysroot = repository_rule(
    implementation = _sysroot,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/wasm/sysroot.BUILD.tpl")),
    },
)

def _config(ctx):
    """Configure Clang and LLD for modules hosted by Emscripten.

    Args:
        ctx: Rule context whose headers attribute supplies the target sysroot.

    Returns:
        CcToolchainConfigInfo for the wasm32 target.
    """
    headers = ctx.attr.headers.label.workspace_root
    compile_actions = [ACTION_NAMES.c_compile, ACTION_NAMES.cpp_compile]
    link_actions = [ACTION_NAMES.cpp_link_executable, ACTION_NAMES.cpp_link_dynamic_library, ACTION_NAMES.cpp_link_nodeps_dynamic_library]
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = [
            feature(name = "supports_pic", enabled = True),
            feature(name = "opt", flag_sets = [flag_set(actions = compile_actions, flag_groups = [flag_group(flags = ["-O3", "-DNDEBUG"])])]),
            feature(name = "dbg", flag_sets = [flag_set(actions = compile_actions, flag_groups = [flag_group(flags = ["-O0", "-g"])])]),
            feature(name = "wasm", enabled = True, flag_sets = [
                flag_set(actions = compile_actions + link_actions, flag_groups = [flag_group(flags = ["--target=wasm32-unknown-emscripten"])]),
                flag_set(actions = compile_actions, flag_groups = [flag_group(flags = [
                    "-resource-dir",
                    RESOURCE_INCLUDE.removesuffix("/include"),
                    "-fPIC",
                    "-fvisibility=hidden",
                    "-fno-exceptions",
                    "-fno-rtti",
                    "-Werror=missing-declarations",
                    "-msimd128",
                ])]),
                flag_set(actions = [ACTION_NAMES.cpp_compile], flag_groups = [flag_group(flags = [
                    "-std=c++26",
                    "-fvisibility-inlines-hidden",
                    "-nostdinc++",
                    "-isystem",
                    headers + "/c++/v1",
                    "-isystem",
                    headers + "/compat",
                    "-isystem",
                    headers,
                ])]),
                flag_set(actions = [ACTION_NAMES.c_compile], flag_groups = [flag_group(flags = ["-xc", "-std=c23", "-isystem", headers])]),
                # The embedding application supplies shared memory, table and
                # runtime imports. Clang and LLD emit the module directly.
                flag_set(actions = link_actions, flag_groups = [flag_group(flags = [
                    "-nostdlib",
                    "-Wl,--no-entry",
                    "-Wl,--import-memory",
                    "-Wl,--experimental-pic",
                    "-Wl,--unresolved-symbols=import-dynamic",
                ])]),
                # PIE lets hosted executables import shared modules. LLD's
                # ordinary executable mode searches only static archives.
                flag_set(actions = [ACTION_NAMES.cpp_link_executable], flag_groups = [flag_group(flags = ["-Wl,--pie"])]),
            ]),
        ],
        tool_paths = [tool_path(name = name, path = path) for name, path in [
            ("gcc", CXX),
            ("ld", WASM_LINKER),
            ("ar", AR),
            ("cpp", CPP),
            ("gcov", COV),
            ("nm", NM),
            ("objdump", OBJDUMP),
            ("strip", STRIP),
        ]],
        cxx_builtin_include_directories = [RESOURCE_INCLUDE, headers],
        toolchain_identifier = "clang-wasm32",
        host_system_name = HOST_SYSTEM,
        target_system_name = "wasm32",
        target_cpu = "wasm32",
        target_libc = "emscripten",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "4.0.20",
    )

wasm_cc_toolchain_config = rule(
    implementation = _config,
    attrs = {"headers": attr.label(mandatory = True)},
    provides = [CcToolchainConfigInfo],
)

# These labels form the WebAssembly portion of Toolchain's root registration
# surface for modules hosted by an Emscripten application.
# buildifier: disable=unnamed-macro
def wasm_targets():
    """Declare the Emscripten sysroot, compiler, platform and selection key."""
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
        name = "web",
        constraint_values = [
            "@platforms//os:emscripten",
            "@platforms//cpu:wasm32",
        ],
    )
