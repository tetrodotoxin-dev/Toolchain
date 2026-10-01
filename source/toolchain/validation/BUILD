load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = [
        "benchmark.hpp",
        "clock.hpp",
        "harness.hpp",
        "unit_test.hpp",
    ],
    includes = ["../.."],
)

cc_library(
    name = "clock",
    srcs = ["clock.cpp"],
    deps = [":headers"],
)

cc_library(
    name = "test",
    srcs = ["unit_test.cpp"],
    deps = [
        ":clock",
        ":headers",
    ],
)

cc_library(
    name = "benchmark",
    srcs = ["benchmark.cpp"],
    deps = [
        ":clock",
        ":headers",
    ],
)

filegroup(
    name = "sources",
    srcs = glob(["**"]),
)
