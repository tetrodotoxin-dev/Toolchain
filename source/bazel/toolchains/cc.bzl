# Copyright (c) 2023-present Matt Kaes and contributors

"""Configure the shared LLVM tools for Linux, Windows and Web targets.

The execution host selects the compiler binaries; each target selects its SDK
and ABI. Linux releases retain x86-64-v3 with RDRAND, glibc 2.35 and dynamic
libstdc++. Hosted Web modules import their runtime from the embedding program;
standalone Web validation links Emscripten's runtime for execution in Node.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "env_entry",
    "env_set",
    "feature",
    "flag_group",
    "flag_set",
    "tool_path",
)
load(
    "@host_tools//:settings.bzl",
    "AR",
    "ARCHIVER",
    "CLANG",
    "COV",
    "CPP",
    "CXX",
    "ELF_LINKER",
    "HOST_SYSTEM",
    "LINKER",
    "NM",
    "OBJDUMP",
    "PATH",
    "PYTHON",
    "RESOURCE_INCLUDE",
    "STRIP",
    "TEMP",
    "WASM_LINKER",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

# Pinned rules_cc 0.2.17 provides its MSVC configuration at this private path.
# Reusing it keeps the Windows action grammar and import library handling in
# the upstream implementation. Recheck this path when upgrading rules_cc.
# buildifier: disable=bzl-visibility
load(
    "@rules_cc//cc/private/toolchain:windows_cc_toolchain_config.bzl",
    windows_config = "cc_toolchain_config",
)
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")
load(":toolchains/linux/repository.bzl", _GCC_DIRECTORY = "GCC_DIRECTORY")

_COMPILE = [ACTION_NAMES.c_compile, ACTION_NAMES.cpp_compile]
_LINK = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]
_COMPILE_FLAGS = [
    "-ffile-compilation-dir=.",
    "-ffile-prefix-map=" + RESOURCE_INCLUDE + "=toolchain/clang/include",
    "-ffile-reproducible",
    "-Wno-builtin-macro-redefined",
    '-D__DATE__="redacted"',
    '-D__TIME__="redacted"',
    '-D__TIMESTAMP__="redacted"',
]

def _flags(name, actions, flags, enabled = True):
    """Apply one ordered flag list to the selected compiler actions."""
    return feature(
        name = name,
        enabled = enabled,
        flag_sets = [flag_set(actions = actions, flag_groups = [flag_group(flags = flags)])],
    )

def _create_config(
        ctx,
        features,
        tools,
        includes,
        identifier,
        compiler = "clang",
        linux = False):
    """Share language policy while each target supplies its ABI and runtime."""
    common = [
        feature(name = "supports_pic", enabled = True),
        _flags("opt", _COMPILE, ["-O3", "-DNDEBUG"], False),
        _flags("dbg", _COMPILE, ["-O0", "-g"], False),
        _flags(
            "cpp_language",
            [ACTION_NAMES.cpp_compile],
            ["-std=c++26", "-fvisibility-inlines-hidden"],
        ),
        _flags("c_language", [ACTION_NAMES.c_compile], ["-xc", "-std=c23"]),
    ]

    if not linux:
        common.append(
            _flags(
                "common_compile",
                _COMPILE,
                _COMPILE_FLAGS +
                [
                    "-fPIC",
                    "-fvisibility=hidden",
                    "-fno-exceptions",
                    "-fno-rtti",
                    "-Werror=missing-declarations",
                    "-msimd128",
                ],
            ),
        )

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = common + features,
        tool_paths = [tool_path(name = name, path = path) for name, path in tools.items()],
        cxx_builtin_include_directories = includes,
        toolchain_identifier = identifier,
        host_system_name = HOST_SYSTEM,
        target_system_name = "linux" if linux else "wasm32",
        target_cpu = "x86_64" if linux else "wasm32",
        target_libc = "glibc" if linux else "emscripten",
        compiler = compiler,
        abi_version = "system-v" if linux else "unknown",
        abi_libc_version = "glibc" if linux else "4.0.20",
    )

def _clang_config(ctx):
    """Configure direct Clang compilation against the selected target SDK."""
    headers = ctx.attr.headers.label.workspace_root
    linux = ctx.attr.target == "linux"
    if linux:
        features = [
            _flags("reproducible_compile", _COMPILE, _COMPILE_FLAGS),
            _flags(
                "target_sdk",
                _COMPILE + _LINK,
                [
                    "--target=x86_64-linux-gnu",
                    "--sysroot=" + headers,
                    "--gcc-install-dir=" + headers + "/" + _GCC_DIRECTORY,
                ],
            ),
            feature(
                name = "pic",
                enabled = True,
                flag_sets = [
                    flag_set(
                        actions = _COMPILE,
                        flag_groups = [
                            flag_group(flags = ["-fPIC"], expand_if_available = "pic"),
                        ],
                    ),
                ],
            ),
            _flags(
                "common_compile",
                _COMPILE,
                [
                    "-Wall",
                    "-Werror",
                    "-Wmissing-declarations",
                    "-fvisibility=hidden",
                    "-fno-exceptions",
                    "-fno-rtti",
                    "-march=x86-64-v3",
                    "-mrdrnd",
                    "-pthread",
                    "-no-canonical-prefixes",
                    "-resource-dir",
                    RESOURCE_INCLUDE.removesuffix("/include"),
                ],
            ),
            _flags(
                "default_linker_flags",
                _LINK,
                ["-lstdc++", "-fuse-ld=lld", "-pthread"],
            ),
        ]
    else:
        features = [
            _flags(
                "wasm_target",
                _COMPILE + _LINK,
                ["--target=wasm32-unknown-emscripten"],
            ),
            _flags(
                "resource_headers",
                _COMPILE,
                ["-resource-dir", RESOURCE_INCLUDE.removesuffix("/include")],
            ),
            _flags(
                "cpp_headers",
                [ACTION_NAMES.cpp_compile],
                [
                    "-nostdinc++",
                    "-isystem",
                    headers + "/c++/v1",
                    "-isystem",
                    headers + "/compat",
                    "-isystem",
                    headers,
                ],
            ),
            _flags("c_headers", [ACTION_NAMES.c_compile], ["-isystem", headers]),
            # The embedding application supplies shared memory, table and
            # runtime imports. Clang and LLD emit the module directly.
            _flags(
                "hosted_link",
                _LINK,
                [
                    "-nostdlib",
                    "-Wl,--no-entry",
                    "-Wl,--import-memory",
                    "-Wl,--experimental-pic",
                    "-Wl,--unresolved-symbols=import-dynamic",
                ],
            ),
            # PIE lets hosted executables import shared modules. LLD's
            # ordinary executable mode searches only static archives.
            _flags("hosted_pie", [ACTION_NAMES.cpp_link_executable], ["-Wl,--pie"]),
        ]

    return _create_config(
        ctx = ctx,
        features = features,
        tools = {
            "gcc": CXX,
            "ld": ELF_LINKER if linux else WASM_LINKER,
            "ar": AR,
            "cpp": CPP,
            "gcov": COV,
            "nm": NM,
            "objdump": OBJDUMP,
            "strip": STRIP,
        },
        includes = [RESOURCE_INCLUDE, headers],
        identifier = "clang-linux-x86_64" if linux else "clang-wasm32",
        linux = linux,
    )

clang_cc_toolchain_config = rule(
    implementation = _clang_config,
    attrs = {
        "headers": attr.label(mandatory = True),
        "target": attr.string(mandatory = True, values = ["linux", "wasm"]),
    },
    provides = [CcToolchainConfigInfo],
)

def _runner_config(ctx):
    """Configure Emscripten to link standalone Node validation programs."""
    sdk = ctx.attr.sdk.label.workspace_root
    resource_directory = sdk + "/lib/clang/22"
    sysroot_include = sdk + "/emscripten/cache/sysroot/include"
    tools = {}
    for target, name in ctx.attr.tools.items():
        files = target[DefaultInfo].files.to_list()
        if len(files) != 1:
            fail("Web tool " + name + " must supply exactly one executable file")

        tools[name] = files[0].path.removeprefix(sdk + "/")

    return _create_config(
        ctx = ctx,
        features = [
            feature(
                name = "emscripten_environment",
                enabled = True,
                env_sets = [
                    env_set(
                        actions = _COMPILE + _LINK,
                        env_entries = [
                            env_entry(key = "EM_NODE_JS", value = ctx.file.node.path),
                            env_entry(key = "PYTHON", value = PYTHON),
                            env_entry(key = "EMSDK_PYTHON", value = PYTHON),
                            env_entry(key = "PYTHONDONTWRITEBYTECODE", value = "1"),
                        ],
                    ),
                ],
            ),
            _flags(
                "runner_compile",
                _COMPILE,
                [
                    "-Wall",
                    "-Werror",
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
                ],
            ),
            _flags(
                "runner_link",
                _LINK,
                [
                    "-sSINGLE_FILE=1",
                    "-sENVIRONMENT=node",
                    "-sEXIT_RUNTIME=1",
                    # Validation retains the same large stack fixtures used by
                    # native builds instead of weakening their geometry for Wasm.
                    "-sSTACK_SIZE=8388608",
                    # A fixed heap retains the allocator suite's large-capacity
                    # cases without changing their memory-growth behavior.
                    "-sINITIAL_MEMORY=268435456",
                ],
            ),
            feature(
                name = "wasm_threads",
                flag_sets = [
                    flag_set(
                        actions = _COMPILE,
                        flag_groups = [flag_group(flags = ["-pthread"])],
                    ),
                    flag_set(
                        actions = _LINK,
                        flag_groups = [
                            flag_group(
                                flags = [
                                    "-pthread",
                                    "-sPTHREAD_POOL_SIZE=4",
                                ],
                            ),
                        ],
                    ),
                ],
            ),
        ],
        tools = tools,
        includes = [
            "%workspace%/" + path
            for path in [
                resource_directory + "/include",
                sysroot_include + "/c++/v1",
                sysroot_include + "/compat",
                sysroot_include,
            ]
        ],
        identifier = "emscripten-validation-runner",
        compiler = "emscripten",
    )

wasm_runner_cc_toolchain_config = rule(
    implementation = _runner_config,
    attrs = {
        "node": attr.label(mandatory = True, allow_single_file = True),
        "sdk": attr.label(mandatory = True),
        "tools": attr.label_keyed_string_dict(allow_files = True, mandatory = True),
    },
    provides = [CcToolchainConfigInfo],
)

def _host_tool(path):
    """Resolve a host executable from the execution root without embedding it."""
    package_root = Label("//:windows").workspace_root
    prefix = "../" * len(package_root.split("/")) if package_root else ""
    return prefix + Label("@host_tools//:files").workspace_root + "/" + path

def _windows_config():
    """Supply our compiler options and SDK to the upstream MSVC grammar."""
    sdk = Label("@windows_sdk//:files").workspace_root
    windows_config(
        name = "windows_config",
        tags = ["manual"],
        abi_version = "msvc",
        all_compile_flags = [
                                "/Brepro",
                                "/X",
                                "/clang:-gno-codeview-command-line",
                                "/clang:-resource-dir=" + RESOURCE_INCLUDE.removesuffix("/include"),
                                "/clang:-ivfsoverlay",
                                "/clang:" + sdk + "/case.yaml",
                                "/clang:-mavx2",
                                "/clang:-mrdrnd",
                                "/clang:-march=x86-64-v3",
                                "/DNOMINMAX",
                                "/D_CRT_SECURE_NO_WARNINGS",
                                "/clang:-fno-exceptions",
                                "/clang:-fno-rtti",
                                "/clang:-Werror=missing-declarations",
                            ] +
                            ["/clang:" + flag for flag in _COMPILE_FLAGS] +
                            ["/imsvc" + RESOURCE_INCLUDE] +
                            [
                                "/imsvc" + sdk + "/include/" + part
                                for part in ["crt", "ucrt", "shared", "um", "winrt"]
                            ],
        archiver_flags = [],
        compiler = "clang-cl",
        conly_flags = ["/clang:-std=c23"],
        cpu = "x64_windows",
        cxx_builtin_include_directories = [RESOURCE_INCLUDE, sdk + "/include"],
        cxx_flags = ["/std:c++latest"],
        dbg_mode_debug_flag = "/DEBUG:FULL",
        fastbuild_mode_debug_flag = "/DEBUG:FULL",
        default_link_flags = [
                                 "/timestamp:0",
                                 "/pdbaltpath:%%_PDB%%",
                                 "/pdbsourcepath:.",
                                 "/lldignoreenv",
                                 "/vfsoverlay:" + sdk + "/case.yaml",
                             ] +
                             ["/LIBPATH:" + sdk + "/lib/" + part for part in ["crt", "ucrt", "um"]],
        host_system_name = HOST_SYSTEM,
        msvc_cl_path = _host_tool("llvm/bin/" + CLANG.split("/")[-1]),
        msvc_env_include = sdk + "/include/crt",
        msvc_env_lib = sdk + "/lib/crt",
        msvc_env_path = PATH,
        msvc_env_tmp = TEMP,
        msvc_lib_path = _host_tool(
            ("llvm/bin/" if "/llvm/bin/" in ARCHIVER else "") + ARCHIVER.split("/")[-1],
        ),
        msvc_link_path = _host_tool("llvm/bin/" + LINKER.split("/")[-1]),
        msvc_ml_path = _host_tool("llvm/bin/" + CLANG.split("/")[-1]),
        target_libc = "ucrt",
        target_system_name = "windows",
        toolchain_identifier = "clang-windows-x64",
        win32_winnt_flag = "/D_WIN32_WINNT=0x0A00",
    )

def _register(name, cpu, os, toolchain, runtime = None):
    native.toolchain(
        name = "cc_toolchain_for_" + name,
        exec_compatible_with = [
            "@platforms//cpu:x86_64",
            "@platforms//os:" + HOST_SYSTEM,
        ],
        target_compatible_with = ["@platforms//cpu:" + cpu, "@platforms//os:" + os] +
                                 ([runtime] if runtime else []),
        toolchain = toolchain,
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

# The root bootstrap owns the fixed platform and compiler labels registered by
# MODULE.bazel. Acquisition rules keep SDK files cached independently of these
# declarations and the machine-specific host settings.
# buildifier: disable=unnamed-macro
def toolchains():
    """Declare the native and Web platforms, configurations and registrations."""
    for setting, platform, os in [
        ("linux", "linux_x86_64", "linux"),
        ("windows", "windows_x64", "windows"),
    ]:
        constraints = ["@platforms//os:" + os, "@platforms//cpu:x86_64"]
        native.config_setting(name = setting, constraint_values = constraints)
        native.platform(name = platform, constraint_values = constraints)

    native.constraint_setting(name = "wasm_runtime")
    native.constraint_value(name = "wasm_hosted", constraint_setting = ":wasm_runtime")
    native.constraint_value(name = "wasm_standalone", constraint_setting = ":wasm_runtime")
    for platform, runtime in [
        ("wasm32", ":wasm_hosted"),
        ("wasm32_runner", ":wasm_standalone"),
    ]:
        native.platform(
            name = platform,
            constraint_values = [
                "@platforms//cpu:wasm32",
                "@platforms//os:emscripten",
                runtime,
            ],
        )

    native.config_setting(
        name = "web",
        constraint_values = ["@platforms//os:emscripten", "@platforms//cpu:wasm32"],
    )

    clang_cc_toolchain_config(
        name = "linux_x86_64_toolchain_config",
        target = "linux",
        headers = "@linux_sdk//:files",
        tags = ["manual"],
    )

    native.filegroup(
        name = "linux_compiler_files",
        srcs = ["@host_tools//:files", "@linux_sdk//:compiler"],
        tags = ["manual"],
    )

    native.filegroup(
        name = "linux_linker_files",
        srcs = ["@host_tools//:files", "@linux_sdk//:linker"],
        tags = ["manual"],
    )

    native.filegroup(
        name = "linux_files",
        srcs = [":linux_compiler_files", ":linux_linker_files"],
        tags = ["manual"],
    )

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

    clang_cc_toolchain_config(
        name = "wasm32_config",
        target = "wasm",
        headers = "@emscripten_sysroot//:headers",
        tags = ["manual"],
    )

    native.filegroup(
        name = "wasm_files",
        srcs = ["@host_tools//:files", "@emscripten_sysroot//:headers"],
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

    _windows_config()

    # The empty group satisfies auxiliary action slots in the MSVC rule.
    native.filegroup(name = "windows_empty")
    native.filegroup(
        name = "windows_files",
        srcs = ["@host_tools//:files", "@windows_sdk//:files"],
        tags = ["manual"],
    )

    cc_toolchain(
        name = "windows_toolchain",
        all_files = ":windows_files",
        ar_files = ":windows_files",
        as_files = ":windows_empty",
        compiler_files = ":windows_files",
        dwp_files = ":windows_empty",
        linker_files = ":windows_files",
        objcopy_files = ":windows_empty",
        strip_files = ":windows_empty",
        supports_param_files = 1,
        toolchain_config = ":windows_config",
        tags = ["manual"],
    )

    _register("linux_x86_64", "x86_64", "linux", ":linux_x86_64_toolchain")
    _register("windows_x64", "x86_64", "windows", ":windows_toolchain")
    _register("wasm32", "wasm32", "emscripten", ":wasm32_toolchain", ":wasm_hosted")

    # Emscripten tool paths must stay relative to their SDK repository.
    _register(
        "wasm32_runner",
        "wasm32",
        "emscripten",
        "@emscripten_sdk//:toolchain",
        ":wasm_standalone",
    )
