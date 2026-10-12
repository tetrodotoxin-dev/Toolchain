# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:toolchains/registry.bzl", "toolchains")

package(default_visibility = ["//visibility:public"])

exports_files([
    "defs.bzl",
])

toolchains()
