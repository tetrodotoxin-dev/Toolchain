"""Consume and repackage the generated Toolchain validation SDK."""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@tetro_toolchain//:defs.bzl", "format", "library", "package", "validation", "vscode")

package(
    name = "repack",
    components = {
        "api": ["public"],
        "public": [],
    },
    linkage = "{linkage}",
    module = "toolchain_test",
    platforms = ["{platform}"],
)

format()

validation(deps = [])

vscode()

library(
    name = "consumer_library",
    srcs = ["library.c"],
    implementation_deps = [":api"],
    linkage = "shared",
    module = "toolchain_consumer",
)

cc_binary(
    # Separate applications keep their selected runtime closures together.
    # Windows stages dependency DLLs beside each executable.
    name = "alternate/consumer",
    linkstatic = False,
    srcs = ["dependency.c"],
    local_defines = ["EXPECT_STATIC={alternate_static}"],
    deps = ["@alternate//:tetro_toolchain"],
)

cc_binary(
    name = "consumer",
    linkstatic = False,
    srcs = ["consumer.c"],
    local_defines = ["EXPECT_STATIC={static}"],
    deps = [":toolchain_test"],
)

cc_binary(
    name = "component",
    linkstatic = False,
    srcs = ["consumer.c"],
    local_defines = [
        "EXPECT_STATIC={static}",
        "EXPECT_COMPONENT=1",
    ],
    deps = [":api"],
)
