# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:targets.bzl", "toolchains")

package(default_visibility = ["//visibility:public"])

toolchains()

filegroup(
    name = "sources",
    srcs = [
        ".bazelrc",
        ".bazelversion",
        ".clang-format",
        "BUILD",
        "LICENSE",
        "MODULE.bazel",
        "//source:sources",
        "//tests:sources",
    ],
)
