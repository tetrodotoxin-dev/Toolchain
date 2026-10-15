load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = [
        "toolchain/export.h",
        "toolchain/compile/allocation.hpp",
        "toolchain/compile/source_location.hpp",
        "toolchain/memory/lifetime.hpp",
        "toolchain/toolchain.h",
        "toolchain/toolchain.hpp",
    ],
    includes = ["."],
)

filegroup(
    name = "compile_allocation_header",
    srcs = ["toolchain/compile/allocation.hpp"],
    testonly = True,
)

filegroup(
    name = "compile_allocation_dependencies",
    srcs = [
        "toolchain/export.h",
        "toolchain/memory/lifetime.hpp",
        "toolchain/toolchain.h",
    ],
    testonly = True,
)

filegroup(
    name = "sources",
    srcs = glob(["sdk/**"]) + [
        "BUILD",
        "toolchain/export.h",
        "toolchain/compile/allocation.hpp",
        "toolchain/compile/source_location.hpp",
        "toolchain/memory/lifetime.hpp",
        "toolchain/toolchain.h",
        "toolchain/toolchain.hpp",
        "//source/bazel:sources",
        "//source/toolchain/validation:sources",
        "//source/vscode:sources",
    ],
)

exports_files(glob(["sdk/**"]))
