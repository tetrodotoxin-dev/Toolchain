# Copyright (c) 2023-present Matt Kaes and contributors

filegroup(
    name = "compiler",
    srcs = glob(["usr/include/**"]) + ["__GCC_DIRECTORY__/crtbegin.o"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "linker",
    srcs = glob([
        "usr/lib/**",
        "lib/**",
        "lib64/**",
    ]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "files",
    srcs = [
        ":compiler",
        ":linker",
    ],
    visibility = ["//visibility:public"],
)
