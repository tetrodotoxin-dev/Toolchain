load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

_HEADERS = [
    "toolchain/export.h",
    "toolchain/compile/allocation.hpp",
    "toolchain/compile/source_location.hpp",
    "toolchain/memory/lifetime.hpp",
    "toolchain/toolchain.h",
    "toolchain/toolchain.hpp",
]

filegroup(
    name = "header_files",
    srcs = _HEADERS,
)

cc_library(
    name = "headers",
    hdrs = _HEADERS,
    includes = ["."],
)

filegroup(
    name = "compile_allocation_header",
    testonly = True,
    srcs = ["toolchain/compile/allocation.hpp"],
)

filegroup(
    name = "compile_allocation_dependencies",
    testonly = True,
    srcs = [
        "toolchain/export.h",
        "toolchain/memory/lifetime.hpp",
        "toolchain/toolchain.h",
    ],
)

filegroup(
    name = "sources",
    srcs = glob(["sdk/**"]) + [
        "BUILD",
        "toolchain/compile/allocation.hpp",
        "toolchain/compile/source_location.hpp",
        ":header_files",
        "//source/bazel:sources",
        "//source/toolchain/validation:sources",
        "//source/vscode:sources",
    ],
)

exports_files(glob(["sdk/**"]))
