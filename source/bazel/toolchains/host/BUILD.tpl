# Copyright (c) 2023-present Matt Kaes and contributors

load(":settings.bzl", "TOOLS")

exports_files(["settings.bzl"] + TOOLS)

# Individual tools let tests declare their inputs without adding the whole
# compiler installation to their runfiles.
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
