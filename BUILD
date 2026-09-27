# Copyright (c) 2023-present Matt Kaes and contributors
load("//source:targets.bzl", "toolchains")
package(default_visibility = ["//visibility:public"])

toolchains()

filegroup(
    name = "sources",
    srcs = glob(["*.bzl", "*.py"]) + [
        "BUILD", "MODULE.bazel", "LICENSE", ".bazelrc", ".bazelversion", ".clang-format",
        "//source:sources", "//tests:sources",
    ],
)
