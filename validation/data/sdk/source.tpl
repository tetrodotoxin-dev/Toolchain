# Copyright (c) 2023-present Matt Kaes and contributors

"""Reuse the imported component's declared header interface during repackaging."""

alias(
    name = "toolchain_test",
    actual = "@toolchain_test",
    visibility = ["//visibility:public"],
)

alias(
    name = "api",
    actual = "@toolchain_test//:api",
    visibility = ["//visibility:public"],
)

alias(
    name = "public",
    actual = "@toolchain_test//:public",
    visibility = ["//visibility:public"],
)
