# Copyright (c) 2023-present Matt Kaes and contributors

load("@tetro_toolchain//source/bazel:toolchains/wasm/sdk.bzl", "wasm_sdk_files")

package(default_visibility = ["//visibility:public"])

exports_files([
    "emscripten/em++",
])

wasm_sdk_files(
    name = "files",
    root = __ROOT__,
    srcs = glob(["**"]),
)
