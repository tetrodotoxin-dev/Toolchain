# Copyright (c) 2023-present Matt Kaes and contributors

load(":settings.bzl", "TOOLS")

exports_files(["settings.bzl"] + TOOLS)

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
