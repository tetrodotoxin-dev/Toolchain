# Copyright (c) 2023-present Matt Kaes and contributors

"""WebAssembly toolchains for hosted modules and standalone validation."""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "env_entry", "env_set", "feature", "flag_group", "flag_set", "tool_path")
load("@host_tools//:settings.bzl", "AR", "COV", "CPP", "CXX", "HOST_SYSTEM", "NM", "OBJDUMP", "PYTHON", "RESOURCE_INCLUDE", "STRIP", "WASM_LINKER")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")
load(":toolchains/reproducible.bzl", "COMPILE_FLAGS")
load(":toolchains/wasm/sdk.bzl", "WasmToolsInfo")

_COMPILE = [ACTION_NAMES.c_compile, ACTION_NAMES.cpp_compile]
_LINK = [ACTION_NAMES.cpp_link_executable, ACTION_NAMES.cpp_link_dynamic_library, ACTION_NAMES.cpp_link_nodeps_dynamic_library]

def _flags(name, actions, flags, enabled = True):
    """Apply one ordered flag list to the selected compiler actions."""
    return feature(name = name, enabled = enabled, flag_sets = [flag_set(actions = actions, flag_groups = [flag_group(flags = flags)])])

def _common_features():
    """Keep language, optimization and portability policy equal in both modes."""
    return [
        feature(name = "supports_pic", enabled = True),
        _flags("opt", _COMPILE, ["-O3", "-DNDEBUG"], False),
        _flags("dbg", _COMPILE, ["-O0", "-g"], False),
        _flags("common_compile", _COMPILE, COMPILE_FLAGS + [
            "-fPIC",
            "-fvisibility=hidden",
            "-fno-exceptions",
            "-fno-rtti",
            "-Werror=missing-declarations",
            "-msimd128",
        ]),
        _flags("cpp_language", [ACTION_NAMES.cpp_compile], ["-std=c++26", "-fvisibility-inlines-hidden"]),
        _flags("c_language", [ACTION_NAMES.c_compile], ["-xc", "-std=c23"]),
    ]

def _create_config(ctx, features, tools, includes, identifier, compiler):
    """Share the target ABI while each mode supplies its runtime and tools."""
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = _common_features() + features,
        tool_paths = [tool_path(name = name, path = path) for name, path in tools.items()],
        cxx_builtin_include_directories = includes,
        toolchain_identifier = identifier,
        host_system_name = HOST_SYSTEM,
        target_system_name = "wasm32",
        target_cpu = "wasm32",
        target_libc = "emscripten",
        compiler = compiler,
        abi_version = "unknown",
        abi_libc_version = "4.0.20",
    )

def _config(ctx):
    """Configure Clang and LLD for modules hosted by Emscripten.

    Args:
        ctx: Rule context whose headers attribute supplies the target sysroot.

    Returns:
        CcToolchainConfigInfo for the wasm32 target.
    """
    headers = ctx.attr.headers.label.workspace_root
    return _create_config(
        ctx = ctx,
        features = [
            _flags("wasm_target", _COMPILE + _LINK, ["--target=wasm32-unknown-emscripten"]),
            _flags("resource_headers", _COMPILE, ["-resource-dir", RESOURCE_INCLUDE.removesuffix("/include")]),
            _flags("cpp_headers", [ACTION_NAMES.cpp_compile], [
                "-nostdinc++",
                "-isystem", headers + "/c++/v1",
                "-isystem", headers + "/compat",
                "-isystem", headers,
            ]),
            _flags("c_headers", [ACTION_NAMES.c_compile], ["-isystem", headers]),
            # The embedding application supplies shared memory, table and
            # runtime imports. Clang and LLD emit the module directly.
            _flags("hosted_link", _LINK, [
                "-nostdlib",
                "-Wl,--no-entry",
                "-Wl,--import-memory",
                "-Wl,--experimental-pic",
                "-Wl,--unresolved-symbols=import-dynamic",
            ]),
            # PIE lets hosted executables import shared modules. LLD's
            # ordinary executable mode searches only static archives.
            _flags("hosted_pie", [ACTION_NAMES.cpp_link_executable], ["-Wl,--pie"]),
        ],
        tools = {
            "gcc": CXX,
            "ld": WASM_LINKER,
            "ar": AR,
            "cpp": CPP,
            "gcov": COV,
            "nm": NM,
            "objdump": OBJDUMP,
            "strip": STRIP,
        },
        includes = [RESOURCE_INCLUDE, headers],
        identifier = "clang-wasm32",
        compiler = "clang",
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
    resource_directory = sdk + "/lib/clang/22"
    sysroot_include = sdk + "/emscripten/cache/sysroot/include"
    return _create_config(
        ctx = ctx,
        features = [
            feature(name = "emscripten_environment", enabled = True, env_sets = [env_set(
                actions = _COMPILE + _LINK,
                env_entries = [
                    env_entry(key = "EM_NODE_JS", value = ctx.attr.node[WasmToolsInfo].paths["node"]),
                    env_entry(key = "PYTHON", value = PYTHON),
                    env_entry(key = "EMSDK_PYTHON", value = PYTHON),
                    env_entry(key = "PYTHONDONTWRITEBYTECODE", value = "1"),
                ],
            )]),
            _flags("runner_compile", _COMPILE, [
                "-Wall",
                "-Werror",
                "-nostdinc",
                "-resource-dir", resource_directory,
                "-isystem", resource_directory + "/include",
                "-isystem", sysroot_include + "/c++/v1",
                "-isystem", sysroot_include + "/compat",
                "-isystem", sysroot_include,
            ]),
            _flags("runner_link", _LINK, [
                "-sSINGLE_FILE=1",
                "-sENVIRONMENT=node",
                "-sEXIT_RUNTIME=1",
                # Validation retains the same large stack fixtures used by
                # native builds instead of weakening their geometry for Wasm.
                "-sSTACK_SIZE=8388608",
                # A fixed heap retains the allocator suite's large-capacity
                # cases without changing their memory-growth behavior.
                "-sINITIAL_MEMORY=268435456",
            ]),
            feature(name = "wasm_threads", flag_sets = [
                flag_set(actions = _COMPILE, flag_groups = [flag_group(flags = ["-pthread"])]),
                flag_set(actions = _LINK, flag_groups = [flag_group(flags = [
                    "-pthread",
                    "-sPTHREAD_POOL_SIZE=4",
                ])]),
            ]),
        ],
        tools = ctx.attr.sdk[WasmToolsInfo].paths,
        includes = [
            resource_directory + "/include",
            sysroot_include + "/c++/v1",
            sysroot_include + "/compat",
            sysroot_include,
        ],
        identifier = "emscripten-validation-runner",
        compiler = "emscripten",
    )

wasm_runner_cc_toolchain_config = rule(
    implementation = _runner_config,
    attrs = {
        "node": attr.label(mandatory = True, allow_single_file = True),
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
        tags = ["manual"],
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
        tags = ["manual"],
    )

    native.filegroup(name = "wasm_files", srcs = ["@host_tools//:files", "@emscripten_sysroot//:headers"], tags = ["manual"])

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
        tags = ["manual"],
    )

    cc_toolchain(
        name = "wasm32_runner_toolchain",
        all_files = ":wasm_runner_files",
        ar_files = "@emscripten_sdk//:files",
        as_files = "@emscripten_sdk//:files",
        compiler_files = ":wasm_runner_files",
        dwp_files = "@emscripten_sdk//:files",
        linker_files = ":wasm_runner_files",
        objcopy_files = "@emscripten_sdk//:files",
        strip_files = "@emscripten_sdk//:files",
        supports_param_files = 1,
        toolchain_config = ":wasm32_runner_config",
        toolchain_identifier = "emscripten-validation-runner",
        tags = ["manual"],
    )

    native.filegroup(
        name = "wasm_runner_files",
        tags = ["manual"],
        srcs = [
            "@emscripten_node//:node",
            "@emscripten_sdk//:files",
        ],
    )

    native.toolchain(
        name = "cc_toolchain_for_wasm32_runner",
        exec_compatible_with = [
            "@platforms//os:" + HOST_SYSTEM,
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
