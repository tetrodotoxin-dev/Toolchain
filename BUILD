# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:targets.bzl", "toolchains")
load("//source/bazel:validation.bzl", "benchmarks", "tests")

package(default_visibility = ["//visibility:public"])

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
        "//source:sources",
        "//validation:sources",
    ],
)
