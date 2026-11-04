# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:toolchains/cc.bzl", "toolchains")

package(default_visibility=["//visibility:public"])

exports_files(
    [
        ".bazelrc",
        "defs.bzl",
    ]
)

toolchains()
