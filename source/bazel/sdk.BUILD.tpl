# Copyright (c) 2023-present Matt Kaes and contributors

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = glob(
        ["headers/include/**/*.h", "headers/include/**/*.hpp"],
        allow_empty = True,
    ),
    strip_include_prefix = "headers/include",
    defines = select({defines}),
    deps = {dependencies},
)

cc_import(
    name = {library},
    static_library = select({static_libraries}),
    shared_library = select({shared_libraries}),
    interface_library = select({interface_libraries}),
    linkopts = select({linkopts}),
    deps = [":headers"],
)

filegroup(
    name = "build",
    srcs = select({binaries}),
)
