load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@tetro_toolchain//source/bazel:package.bzl", "package_release")

cc_test(
    name = "consumer",
    srcs = ["consumer.c"],
    local_defines = ["EXPECT_STATIC={static}"],
    deps = ["@toolchain_test"],
)

package_release(
    name = "repack",
    project = "toolchain_test",
    {linkage} = "@toolchain_test",
    platforms = ["linux-x86_64-v3"],
    sources = [],
)
