load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = ["export.h"],
    include_prefix = "toolchain",
    strip_include_prefix = ".",
)

filegroup(
    name = "sources",
    srcs = glob(["sdk/**"]) + [
        "BUILD",
        "export.h",
        "//source/bazel:sources",
        "//source/validation:sources",
    ],
)

exports_files(glob(["sdk/**"]))
