load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = [
        "benchmark.hpp",
        "clock.hpp",
        "harness.hpp",
        "stream.hpp",
        "unit_test.hpp",
    ],
    include_prefix = "toolchain",
    strip_include_prefix = "/source",
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
    name = "test_main",
    srcs = ["test_main.cpp"],
    deps = [":test"],
)

cc_library(
    name = "benchmark",
    srcs = ["benchmark.cpp"],
    deps = [
        ":clock",
        ":headers",
    ],
)

cc_library(
    name = "benchmark_main",
    srcs = ["benchmark_main.cpp"],
    deps = [":benchmark"],
)

cc_library(
    name = "stream",
    srcs = ["stream.cpp"],
    deps = [":headers"],
)

filegroup(
    name = "sources",
    srcs = glob(["**"]),
)
