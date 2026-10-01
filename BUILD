# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:targets.bzl", "toolchains")
load(":defs.bzl", "benchmarks", "tests")

package(default_visibility = ["//visibility:public"])

exports_files(["defs.bzl"])

toolchains()

tests(srcs = ["//validation:unit_test.cpp"])

benchmarks(srcs = ["//validation:benchmark.cpp"])

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
