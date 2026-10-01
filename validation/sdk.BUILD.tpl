load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@tetro_toolchain//:defs.bzl", "package")

package(
    name = "repack",
    components = ["api"],
    linkage = "{linkage}",
    module = "toolchain_test",
    platforms = ["linux-x86_64-v3"],
    sources = [],
)

cc_test(
    name = "consumer",
    srcs = ["consumer.c"],
    local_defines = ["EXPECT_STATIC={static}"],
    deps = [":toolchain_test"],
)

cc_test(
    name = "component_consumer",
    srcs = ["consumer.c"],
    local_defines = [
        "EXPECT_STATIC={static}",
        "EXPECT_COMPONENT=1",
    ],
    deps = [":api"],
)
