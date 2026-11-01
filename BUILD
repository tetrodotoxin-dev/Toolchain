# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:toolchains/cc.bzl", "toolchains")
load("//validation/integration:candidate.bzl", "candidate_snapshot")
load("@rules_python//python:py_binary.bzl", "py_binary")
load(":defs.bzl", "format", "validation", "vscode")

package(default_visibility = ["//visibility:public"])

exports_files([
    "defs.bzl",
])

toolchains()

format()

py_binary(
    name = "sdk",
    srcs = ["//source/bazel:release/sdk.py"],
    main = "//source/bazel:release/sdk.py",
    args = [module_name(), module_version()],
    python_version = "3.11.14",
    tags = ["manual"],
)

validation(
    deps = [],
    benchmark_data = ["//validation/integration:validation_benchmark_data"],
    test_data = ["//validation/integration:validation_test_data"],
)

vscode()

# The external-consumer test needs the live Starlark changes before they form a
# clean Git snapshot. This private archive is test input and never a release.
candidate_snapshot()
