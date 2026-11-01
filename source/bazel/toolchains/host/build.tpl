# Copyright (c) 2023-present Matt Kaes and contributors

load("@rules_shell//shell/toolchains:sh_toolchain.bzl", "sh_toolchain")
load(":settings.bzl", "HOST_SYSTEM", "SHELL", "TOOLS")

exports_files(["settings.bzl"] + TOOLS)

# Bazel's test coverage launcher resolves Bash even for ordinary test builds.
# Git for Windows supplies it without requiring its bin directory on PATH.
sh_toolchain(
    name = "shell",
    path = SHELL,
    launcher = "@bazel_tools//tools/launcher" if HOST_SYSTEM == "windows" else None,
    launcher_maker = "@bazel_tools//tools/launcher:launcher_maker" if HOST_SYSTEM == "windows" else None,
    tags = ["manual"],
)

toolchain(
    name = "shell_toolchain",
    toolchain = ":shell",
    toolchain_type = "@rules_shell//shell:toolchain_type",
    exec_compatible_with = ["@platforms//os:" + HOST_SYSTEM],
    target_compatible_with = ["@platforms//os:" + HOST_SYSTEM],
)

# Individual labels give tests the exact host executables present in their
# runfiles. Compiler actions receive the complete files group below.
filegroup(
    name = "files",
    srcs = TOOLS + glob(
        [
            "llvm/lib/clang/**",
            "llvm/lib/libLLVM*.so*",
            "llvm/lib/libclang*.so*",
            "llvm/bin/*.dll",
        ],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)
