load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = ["toolchain/export.h"],
    includes = ["."],
)

filegroup(
    name = "sources",
    srcs = glob(["sdk/**"]) + [
        "BUILD",
        "toolchain/export.h",
        "//source/bazel:sources",
        "//source/toolchain/validation:sources",
        "//source/vscode:sources",
    ],
)

exports_files(glob(["sdk/**"]))
