# Copyright (c) 2023-present Matt Kaes and contributors

package(default_visibility = ["//visibility:public"])

exports_files([
    "bin/node",
])

filegroup(
    name = "node",
    srcs = ["bin/node"],
)

filegroup(
    name = "files",
    srcs = glob(["**"]),
)
