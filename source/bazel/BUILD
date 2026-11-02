# Copyright (c) 2023-present Matt Kaes and contributors

load("@rules_python//python:py_binary.bzl", "py_binary")

package(default_visibility = ["//visibility:public"])

py_binary(
    name = "release_writer",
    srcs = ["release/package.py"],
    main = "release/package.py",
    python_version = "3.11.14",
)

exports_files(glob([
    "**/*.build",
    "**/*.bzl",
    "**/*.cmd",
    "**/*.py",
    "**/*.sh",
    "**/*.tpl",
]) + ["rules/.clang-format"])

filegroup(
    name = "sources",
    srcs = glob([
        "**/*.build",
        "**/*.bzl",
        "**/*.cmd",
        "**/*.py",
        "**/*.sh",
        "**/*.tpl",
    ]) + [
        "BUILD",
        "rules/.clang-format",
    ],
)
