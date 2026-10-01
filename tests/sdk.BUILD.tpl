load("@rules_cc//cc:cc_test.bzl", "cc_test")

cc_test(
    name = "consumer",
    srcs = ["consumer.c"],
    local_defines = ["EXPECT_STATIC={static}"],
    deps = ["@toolchain_test"],
)
