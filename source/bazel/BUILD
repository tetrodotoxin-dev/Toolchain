# Copyright (c) 2023-present Matt Kaes and contributors

package(default_visibility = ["//visibility:public"])

exports_files(
    glob(
        [
            "**/*.build",
            "**/*.bzl",
            "**/*.cmd",
            "**/*.py",
            "**/*.sh",
            "**/*.tpl",
        ],
    ) + [
        "rules/.clang-format",
    ],
)

filegroup(
    name = "sources",
    srcs = glob(
        [
            "**/*.build",
            "**/*.bzl",
            "**/*.cmd",
            "**/*.py",
            "**/*.sh",
            "**/*.tpl",
        ],
    ) + [
        "BUILD",
        "rules/.clang-format",
    ],
)
