# Copyright (c) 2023-present Matt Kaes and contributors

load("@tetro_toolchain//source/bazel:toolchains/cc.bzl", "wasm_runner_cc_toolchain_config")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files([
    "emscripten/em++",
])

filegroup(
    name = "files",
    srcs = glob(["**"]),
)

wasm_runner_cc_toolchain_config(
    name = "config",
    node = "@emscripten_node//:node",
    sdk = ":files",
    tools = __TOOLS__,
    tags = ["manual"],
)

filegroup(
    name = "runner_files",
    srcs = [":files", "@emscripten_node//:node"],
    tags = ["manual"],
)

cc_toolchain(
    name = "toolchain",
    all_files = ":runner_files",
    ar_files = ":files",
    as_files = ":files",
    compiler_files = ":runner_files",
    dwp_files = ":files",
    linker_files = ":runner_files",
    objcopy_files = ":files",
    strip_files = ":files",
    supports_param_files = 1,
    toolchain_config = ":config",
    toolchain_identifier = "emscripten-validation-runner",
    tags = ["manual"],
)
