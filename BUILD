# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:toolchains/cc.bzl", "toolchains")
load("//validation/integration:candidate.bzl", "candidate_snapshot")
load(":defs.bzl", "format", "sdk", "setup", "validation")

package(default_visibility = ["//visibility:public"])

exports_files(
    [
        ".bazelrc",
        "defs.bzl",
    ],
)

toolchains()

format()

sdk(tags = ["manual"])

validation(
    benchmark_data = ["//validation/integration:validation_benchmark_data"],
    test_data = ["//validation/integration:validation_test_data"],
    deps = [],
)

setup()

# The external-consumer test needs the live Starlark changes before they form a
# clean Git snapshot. This private archive is test input and never a release.
candidate_snapshot()
