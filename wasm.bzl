# # Tetrodotoxin
# Copyright (c) 2023-present Matt Kaes and contributors

"""Clang code generation for modules hosted by an Emscripten application."""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "feature", "flag_group", "flag_set", "tool_path")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")

def _sysroot(ctx):
    # Only the target headers are extracted. The compiler, linker and resource
    # headers come from the same installed Clang used for the native build.
    ctx.download_and_extract(
        url = "https://storage.googleapis.com/webassembly/emscripten-releases-builds/linux/c387d7a7e9537d0041d2c3ae71b7538cc978104e/wasm-binaries.tar.xz",
        sha256 = "a06e7ddda0c168f7ad52e6e0509c98db3545dcb254d3b9052e9e6b8423eaee7d",
        strip_prefix = "install/emscripten/cache/sysroot/include",
    )
    ctx.file("BUILD", 'filegroup(name = "headers", srcs = glob(["**"]), visibility = ["//visibility:public"])\n')

emscripten_sysroot = repository_rule(implementation = _sysroot)

def _config(ctx):
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
                    "-fPIC",

                    "-fno-exceptions",
                    "-fno-rtti",
                    "-msimd128",
                ])]),
                flag_set(actions = [ACTION_NAMES.cpp_compile], flag_groups = [flag_group(flags = [
                    "-std=c++26",
                    "-nostdinc++",
                    "-isystem",
                    headers + "/c++/v1",
                    "-isystem",
                    headers + "/compat",
                    "-isystem",
                    headers,
                ])]),
                flag_set(actions = [ACTION_NAMES.c_compile], flag_groups = [flag_group(flags = ["-xc", "-std=c23", "-isystem", headers])]),
                # The embedding application supplies shared memory, table and runtime imports.
                # Clang and LLD emit the module directly, without emcc wrappers.
                flag_set(actions = link_actions, flag_groups = [flag_group(flags = [
                    "-nostdlib",
                    "-Wl,--no-entry",
                    "-Wl,--export-all",
                    "-Wl,--import-memory",
                    "-Wl,--experimental-pic",
                    "-Wl,--unresolved-symbols=import-dynamic",
                ])]),
            ]),
        ],
        tool_paths = [tool_path(name = name, path = path) for name, path in [
            ("gcc", "/usr/bin/clang++"),
            ("ld", "/usr/bin/wasm-ld"),
            ("ar", "/usr/bin/ar"),
            ("cpp", "/usr/bin/clang-cpp"),
            ("gcov", "/bin/false"),
            ("nm", "/usr/bin/nm"),
            ("objdump", "/bin/false"),
            ("strip", "/bin/false"),
        ]],
        cxx_builtin_include_directories = ["/usr/lib/clang", "/usr/lib/llvm-22/lib/clang", headers],
        toolchain_identifier = "clang-wasm32",
        host_system_name = "linux",
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
