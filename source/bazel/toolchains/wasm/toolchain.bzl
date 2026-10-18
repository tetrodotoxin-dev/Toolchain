# Copyright (c) 2023-present Matt Kaes and contributors

"""WebAssembly toolchains for hosted modules and standalone validation."""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "env_entry", "env_set", "feature", "flag_group", "flag_set", "tool_path")
load("@host_tools//:settings.bzl", "AR", "COV", "CPP", "CXX", "HOST_SYSTEM", "NM", "OBJDUMP", "PYTHON", "RESOURCE_INCLUDE", "STRIP", "WASM_LINKER")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")

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

def _runner_config(ctx):
    """Configure Emscripten to link standalone Node validation programs.

    Args:
        ctx: Analysis context selecting the pinned SDK and Node runtime.

    Returns:
        CcToolchainConfigInfo for executable Web validation.
    """
    sdk = ctx.attr.sdk.label.workspace_root
    sdk_tool = "/proc/self/cwd/" + sdk
    node = "/proc/self/cwd/" + ctx.attr.node.label.workspace_root + "/bin/node"
    resource_directory = sdk + "/lib/clang/22"
    sysroot_include = sdk + "/emscripten/cache/sysroot/include"
    compile_actions = [ACTION_NAMES.c_compile, ACTION_NAMES.cpp_compile]
    link_actions = [ACTION_NAMES.cpp_link_executable, ACTION_NAMES.cpp_link_dynamic_library, ACTION_NAMES.cpp_link_nodeps_dynamic_library]
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = [
            feature(name = "supports_pic", enabled = True),
            feature(name = "opt", flag_sets = [flag_set(actions = compile_actions, flag_groups = [flag_group(flags = ["-O3", "-DNDEBUG"])])]),
            feature(name = "dbg", flag_sets = [flag_set(actions = compile_actions, flag_groups = [flag_group(flags = ["-O0", "-g"])])]),
            feature(name = "emscripten_environment", enabled = True, env_sets = [env_set(
                actions = compile_actions + link_actions,
                env_entries = [
                    env_entry(key = "EM_NODE_JS", value = node),
                    env_entry(key = "PYTHON", value = PYTHON),
                ],
            )]),
            feature(name = "runner_compile", enabled = True, flag_sets = [
                flag_set(actions = compile_actions, flag_groups = [flag_group(flags = [
                    "-Wall",
                    "-Werror",
                    "-Wmissing-declarations",
                    "-fPIC",
                    "-fvisibility=hidden",
                    "-fno-exceptions",
                    "-fno-rtti",
                    "-msimd128",
                    "-pthread",
                    "-nostdinc",
                    "-resource-dir",
                    resource_directory,
                    "-isystem",
                    resource_directory + "/include",
                    "-isystem",
                    sysroot_include + "/c++/v1",
                    "-isystem",
                    sysroot_include + "/compat",
                    "-isystem",
                    sysroot_include,
                ])]),
                flag_set(actions = [ACTION_NAMES.cpp_compile], flag_groups = [flag_group(flags = [
                    "-std=c++26",
                    "-fvisibility-inlines-hidden",
                ])]),
                flag_set(actions = [ACTION_NAMES.c_compile], flag_groups = [flag_group(flags = ["-xc", "-std=c23"])]),
            ]),
            feature(name = "runner_link", enabled = True, flag_sets = [flag_set(actions = link_actions, flag_groups = [flag_group(flags = [
                "-pthread",
                "-sSINGLE_FILE=1",
                "-sENVIRONMENT=node",
                "-sEXIT_RUNTIME=1",
                "-sPTHREAD_POOL_SIZE=4",
                # Validation retains the same large stack fixtures used by
                # native builds instead of weakening their geometry for Wasm.
                "-sSTACK_SIZE=8388608",
                # A fixed shared heap avoids cross-thread memory growth while
                # retaining the allocator suite's large-capacity cases.
                "-sINITIAL_MEMORY=268435456",
            ])])]),
        ],
        tool_paths = [tool_path(name = name, path = path) for name, path in [
            ("gcc", sdk_tool + "/emscripten/em++"),
            ("ld", sdk_tool + "/bin/wasm-ld"),
            ("ar", sdk_tool + "/bin/llvm-ar"),
            ("cpp", sdk_tool + "/bin/clang-cpp"),
            ("gcov", sdk_tool + "/bin/llvm-cov"),
            ("nm", sdk_tool + "/bin/llvm-nm"),
            ("objdump", sdk_tool + "/bin/llvm-objdump"),
            ("strip", sdk_tool + "/bin/llvm-strip"),
        ]],
        cxx_builtin_include_directories = [
            resource_directory + "/include",
            sysroot_include + "/c++/v1",
            sysroot_include + "/compat",
            sysroot_include,
        ],
        toolchain_identifier = "emscripten-validation-runner",
        host_system_name = HOST_SYSTEM,
        target_system_name = "wasm32",
        target_cpu = "wasm32",
        target_libc = "emscripten",
        compiler = "emscripten",
        abi_version = "unknown",
        abi_libc_version = "4.0.20",
    )

wasm_runner_cc_toolchain_config = rule(
    implementation = _runner_config,
    attrs = {
        "node": attr.label(mandatory = True),
        "sdk": attr.label(mandatory = True),
    },
    provides = [CcToolchainConfigInfo],
)

# These labels keep hosted SDK modules and executable validation on separate
# platforms. The hosted toolchain preserves the import-only SDK boundary while
# the validation toolchain links an Emscripten runtime that Node can execute.
# buildifier: disable=unnamed-macro
def wasm_targets():
    """Declare hosted and executable Emscripten toolchain surfaces."""
    native.constraint_setting(name = "wasm_runtime")
    native.constraint_value(name = "wasm_hosted", constraint_setting = ":wasm_runtime")
    native.constraint_value(name = "wasm_standalone", constraint_setting = ":wasm_runtime")

    native.platform(
        name = "wasm32",
        constraint_values = [
            "@platforms//cpu:wasm32",
            "@platforms//os:emscripten",
            ":wasm_hosted",
        ],
    )

    native.platform(
        name = "wasm32_runner",
        constraint_values = [
            "@platforms//cpu:wasm32",
            "@platforms//os:emscripten",
            ":wasm_standalone",
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
            ":wasm_hosted",
        ],
        toolchain = ":wasm32_toolchain",
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    wasm_runner_cc_toolchain_config(
        name = "wasm32_runner_config",
        node = "@emscripten_node//:node",
        sdk = "@emscripten_sdk//:files",
    )

    cc_toolchain(
        name = "wasm32_runner_toolchain",
        all_files = ":wasm_runner_files",
        ar_files = "@emscripten_sdk//:files",
        as_files = "@emscripten_sdk//:files",
        compiler_files = "@emscripten_sdk//:files",
        dwp_files = "@emscripten_sdk//:files",
        linker_files = ":wasm_runner_files",
        objcopy_files = "@emscripten_sdk//:files",
        strip_files = "@emscripten_sdk//:files",
        supports_param_files = 1,
        toolchain_config = ":wasm32_runner_config",
        toolchain_identifier = "emscripten-validation-runner",
    )

    native.filegroup(
        name = "wasm_runner_files",
        srcs = [
            "@emscripten_node//:files",
            "@emscripten_sdk//:files",
        ],
    )

    native.toolchain(
        name = "cc_toolchain_for_wasm32_runner",
        exec_compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
        target_compatible_with = [
            "@platforms//cpu:wasm32",
            "@platforms//os:emscripten",
            ":wasm_standalone",
        ],
        toolchain = ":wasm32_runner_toolchain",
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    native.config_setting(
        name = "web",
        constraint_values = [
            "@platforms//os:emscripten",
            "@platforms//cpu:wasm32",
        ],
    )

    native.config_setting(
        name = "web_runner",
        constraint_values = [
            ":wasm_standalone",
        ],
    )
