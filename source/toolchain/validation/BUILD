load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = [
        "benchmark.hpp",
        "bytes.hpp",
        "clock.hpp",
        "harness.hpp",
        "move_only.hpp",
        "test.hpp",
        "tracked_value.hpp",
    ],
    includes = ["../.."],
    deps = ["//source:headers"],
)

cc_library(
    name = "clock",
    srcs = ["clock.cpp"],
    deps = [":headers"],
)

cc_library(
    name = "test",
    srcs = ["test.cpp"],
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
