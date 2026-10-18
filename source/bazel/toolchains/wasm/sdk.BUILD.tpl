# Copyright (c) 2023-present Matt Kaes and contributors

package(default_visibility = ["//visibility:public"])

exports_files([
    "emscripten/em++",
])

filegroup(
    name = "files",
    srcs = glob(["**"]),
)
