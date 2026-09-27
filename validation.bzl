# Copyright (c) 2023-present Matt Kaes and contributors

"""Native validation runners shared by every project."""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_test.bzl", "cc_test")

def test(name, srcs = [], deps = [], **kwargs):
    cc_test(
        name = name,
        srcs = srcs,
        deps = deps + [Label("//source/validation:test_main")],
        **kwargs
    )

def benchmark(name, srcs = [], deps = [], **kwargs):
    cc_binary(
        name = name,
        testonly = True,
        srcs = srcs,
        deps = deps + [Label("//source/validation:benchmark_main")],
        **kwargs
    )
