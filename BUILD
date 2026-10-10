# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:toolchains/registry.bzl", "toolchains")
load(":defs.bzl", "format", "vscode")

package(default_visibility = ["//visibility:public"])

exports_files([
    "defs.bzl",
])

toolchains()

format()

vscode()

filegroup(
    name = "sources",
    srcs = [
        ".bazelrc",
        ".bazelversion",
        "BUILD",
        "LICENSE",
        "MODULE.bazel",
        "defs.bzl",
        "toolchain.json",
        "//source:sources",
        "//validation:sources",
    ],
)
