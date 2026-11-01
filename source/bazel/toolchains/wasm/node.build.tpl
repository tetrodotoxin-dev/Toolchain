# Copyright (c) 2023-present Matt Kaes and contributors

load("@tetro_toolchain//source/bazel:toolchains/wasm/sdk.bzl", "wasm_tools")

package(default_visibility = ["//visibility:public"])

exports_files([
    "__NODE__",
])

wasm_tools(
    name = "node",
    tools = __TOOLS__,
    srcs = ["__NODE__"],
)
