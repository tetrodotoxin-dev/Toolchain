# Copyright (c) 2023-present Matt Kaes and contributors

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "files",
    srcs = glob([
        "include/**",
        "lib/**",
    ]) + ["case.yaml"],
)

filegroup(
    name = "runtime",
    srcs = glob(
        ["runtime/**/*.dll"],
        allow_empty = True,
    ),
)
