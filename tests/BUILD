load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("//source/bazel:library.bzl", "WINDOWS", "shared_library", "static_library")
load("//source/bazel:validation.bzl", "test")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "sources",
    srcs = glob(["**"]),
)

test(
    name = "unit_tests",
    srcs = ["unit_test.cpp"],
)

cc_test(
    name = "reporting",
    size = "small",
    srcs = ["reporting.cpp"],
    deps = [
        "//source/validation:stream",
        "//source/validation:test",
    ],
)

static_library(
    name = "library",
    testonly = True,
    srcs = [
        "library.c",
        "library.cpp",
    ],
    deps = [":library_headers"],
)

cc_library(
    name = "library_headers",
    testonly = True,
    hdrs = ["library.h"],
)

shared_library(
    name = "shared_library",
    testonly = True,
    deps = [":library"],
)

cc_test(
    name = "static_library",
    size = "small",
    srcs = ["library_consumer.c"],
    deps = [":library"],
)

filegroup(
    name = "shared_interface",
    testonly = True,
    srcs = [":shared_library"],
    output_group = "interface_library",
)

cc_import(
    name = "shared_import",
    testonly = True,
    interface_library = select({
        WINDOWS: ":shared_interface",
        "//conditions:default": None,
    }),
    shared_library = ":shared_library",
    deps = [":library_headers"],
)

cc_test(
    name = "shared_linkage",
    size = "small",
    srcs = ["library_consumer.c"],
    deps = [":shared_import"],
)
