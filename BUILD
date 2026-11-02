# Copyright (c) 2023-present Matt Kaes and contributors
load("//source/bazel:toolchains/cc.bzl", "toolchains")
load("//validation/integration:candidate.bzl", "candidate_snapshot")
load("//source/bazel:rules/python.bzl", "python_command")
load(":defs.bzl", "format", "validation", "vscode")

package(default_visibility = ["//visibility:public"])

exports_files([
    "defs.bzl",
])

toolchains()

format()

python_command(
    name = "sdk",
    script = "//source/bazel:release/sdk.py",
    arguments = [module_name(), module_version(), "$(execpath :format)"],
    data = [":format"],
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
