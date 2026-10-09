# Copyright (c) 2023-present Matt Kaes and contributors

package(default_visibility = ["//visibility:public"])

exports_files(glob([
    "**/*.bzl",
    "**/*.py",
    "**/*.tpl",
]) + ["rules/.clang-format.tpl"])

filegroup(
    name = "sources",
    srcs = glob([
        "**/*.bzl",
        "**/*.py",
        "**/*.tpl",
    ]) + [
        "BUILD",
        "rules/.clang-format.tpl",
    ],
)
