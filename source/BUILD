load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = [
        "toolchain/export.h",
        "toolchain/memory/const_allocation.hpp",
        "toolchain/memory/lifetime.hpp",
        "toolchain/toolchain.h",
        "toolchain/toolchain.hpp",
    ],
    includes = ["."],
)

filegroup(
    name = "const_allocation_header",
    srcs = ["toolchain/memory/const_allocation.hpp"],
    testonly = True,
)

filegroup(
    name = "const_allocation_dependencies",
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
        "toolchain/memory/const_allocation.hpp",
        "toolchain/memory/lifetime.hpp",
        "toolchain/toolchain.h",
        "toolchain/toolchain.hpp",
        "//source/bazel:sources",
        "//source/toolchain/validation:sources",
        "//source/vscode:sources",
    ],
)

exports_files(glob(["sdk/**"]))
