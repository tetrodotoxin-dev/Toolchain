# Copyright (c) 2023-present Matt Kaes and contributors

package(default_visibility = ["//visibility:public"])

exports_files([
    "__NODE__",
])

filegroup(
    name = "node",
    srcs = ["__NODE__"],
)
