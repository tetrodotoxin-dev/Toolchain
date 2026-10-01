load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@rules_python//python:py_test.bzl", "py_test")
load("//source/bazel:library.bzl", "shared_library", "static_library")
load("//source/bazel:package.bzl", "package_release")
load("//source/bazel:validation.bzl", "benchmark", "test")
load("//source/bazel:vscode.bzl", "vscode")

package(default_visibility = ["//visibility:public"])

vscode(name = "vscode")

filegroup(
    name = "sources",
    srcs = glob(["**"]),
)

test(
    name = "unit_tests",
    srcs = ["unit_test.cpp"],
)

test(
    name = "reporting",
    size = "small",
    srcs = ["reporting.cpp"],
    tags = ["manual"],
)

benchmark(
    name = "benchmark",
    srcs = ["benchmark.cpp"],
)

test(
    name = "skipped",
    size = "small",
    srcs = ["skipped.cpp"],
)

test(
    name = "empty",
    size = "small",
)

# The reporting example intentionally fails. The outer test checks its exit
# status and output after the same entrypoint used by every consumer returns.
py_test(
    name = "validation",
    size = "small",
    srcs = ["validation.py"],
    args = [
        "$(rlocationpath :unit_tests)",
        "$(rlocationpath :reporting)",
        "$(rlocationpath :benchmark)",
        "$(rlocationpath :skipped)",
        "$(rlocationpath :empty)",
        "$(rlocationpath reporting.cpp)",
    ],
    data = [
        "reporting.cpp",
        ":benchmark",
        ":empty",
        ":reporting",
        ":skipped",
        ":unit_tests",
    ],
    deps = ["@rules_python//python/runfiles"],
)

static_library(
    name = "project_static",
    testonly = True,
    srcs = ["project.c"],
    hdrs = ["project.h"],
)

shared_library(
    name = "project_shared",
    testonly = True,
    srcs = ["project.c"],
    hdrs = ["project.h"],
)

static_library(
    name = "static_implementation",
    testonly = True,
    srcs = [
        "library.c",
        "library.cpp",
    ],
    hdrs = ["library.h"],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = ["TOOLCHAIN_TEST_PRIVATE=1"],
    project = "toolchain_test",
    deps = [":project_static"],
)

shared_library(
    name = "shared_library",
    testonly = True,
    srcs = [
        "library.c",
        "library.cpp",
    ],
    hdrs = ["library.h"],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = ["TOOLCHAIN_TEST_PRIVATE=1"],
    project = "toolchain_test",
    deps = [":project_shared"],
)

cc_test(
    name = "static_library",
    size = "small",
    srcs = ["library_consumer.c"],
    deps = [":static_implementation"],
)

cc_test(
    name = "shared_linkage",
    size = "small",
    srcs = ["library_consumer.c"],
    deps = [":shared_library"],
)

package_release(
    name = "sdk",
    testonly = True,
    project = "toolchain_test",
    shared = ":shared_library",
    sources = [":sources"],
    static = ":static_implementation",
    tags = ["manual"],
)

package_release(
    name = "project_sdk",
    testonly = True,
    shared = ":project_shared",
    sources = [":sources"],
    static = ":project_static",
    tags = ["manual"],
)
