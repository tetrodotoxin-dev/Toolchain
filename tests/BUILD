load("@host_tools//:settings.bzl", "NM")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
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
    hdrs = [
        "private/project_detail.h",
        "project.h",
    ],
    defines = ["TOOLCHAIN_PROJECT_VALUE=1"],
    includes = ["private"],
    deps = [":runtime"],
)

shared_library(
    name = "project_shared",
    testonly = True,
    srcs = ["project.c"],
    hdrs = [
        "private/project_detail.h",
        "project.h",
    ],
    defines = ["TOOLCHAIN_PROJECT_VALUE=1"],
    includes = ["private"],
    deps = [":runtime"],
)

# The SDK must carry a dependency reached through another shared library.
shared_library(
    name = "runtime",
    testonly = True,
    srcs = ["runtime.c"],
    hdrs = ["runtime.h"],
    project = "toolchain_runtime",
    shared_lib_name = select({
        "//:linux": "libruntime.so.1",
        "//:windows": "runtime.dll",
        "//conditions:default": "libruntime.so",
    }),
)

cc_library(
    name = "public",
    hdrs = ["public.h"],
    defines = ["TOOLCHAIN_TEST_PUBLIC=1"],
)

# Shared consumers must not link this implementation archive a second time.
static_library(
    name = "private_static",
    testonly = True,
    srcs = ["private.c"],
    project = "toolchain_private",
    alwayslink = True,
)

static_library(
    name = "static_implementation",
    testonly = True,
    srcs = [
        "library.c",
        "library.cpp",
        "private.c",
    ],
    hdrs = ["library.h"],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    implementation_deps = [":project_static"],
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = ["TOOLCHAIN_TEST_PRIVATE=1"],
    project = "toolchain_test",
    deps = [":public"],
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
    implementation_deps = [
        ":private_static",
        ":project_shared",
        ":runtime",
    ],
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = ["TOOLCHAIN_TEST_PRIVATE=1"],
    project = "toolchain_test",
    deps = [":public"],
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

py_test(
    name = "implementation_deps",
    size = "small",
    srcs = ["implementation_deps.py"],
    args = [
        "$(rlocationpath @host_tools//:llvm/bin/" + NM.split("/")[-1] + ")",
        "$(rlocationpath :shared_linkage)",
        "$(rlocationpath :shared_library_shared)",
    ],
    data = [
        ":shared_library_shared",
        ":shared_linkage",
        "@host_tools//:llvm/bin/" + NM.split("/")[-1],
    ],
    deps = ["@rules_python//python/runfiles"],
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
