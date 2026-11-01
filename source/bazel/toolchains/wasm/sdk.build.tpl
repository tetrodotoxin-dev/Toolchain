# Copyright (c) 2023-present Matt Kaes and contributors

load("@tetro_toolchain//source/bazel:toolchains/wasm/sdk.bzl", "wasm_tools")

package(default_visibility = ["//visibility:public"])

exports_files([
    "emscripten/em++",
])

wasm_tools(
    name = "files",
    paths = __TOOLS__,
    srcs = glob(["**"]),
)
