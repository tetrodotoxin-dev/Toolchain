load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_test.bzl", "cc_test")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "sources",
    srcs = glob(["**"]),
)

cc_binary(
    name = "process_fixture",
    testonly = True,
    srcs = ["process_fixture.c"],
)

cc_test(
    name = "process",
    srcs = ["process.cpp"],
    args = ["$(rootpath :process_fixture)"],
    data = [":process_fixture"],
    deps = [
        "//source/validation:process",
        "//source/validation:test",
    ],
)
