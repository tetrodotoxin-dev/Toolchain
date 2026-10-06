# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:toolchains/registry.bzl", "toolchains")
load(":defs.bzl", "vscode")

package(default_visibility = ["//visibility:public"])

exports_files(["defs.bzl"])

toolchains()

vscode()

filegroup(
    name = "sources",
    srcs = [
        ".bazelrc",
        ".bazelversion",
        ".clang-format",
        "BUILD",
        "LICENSE",
        "MODULE.bazel",
        "defs.bzl",
        "//source:sources",
        "//validation:sources",
    ],
)
