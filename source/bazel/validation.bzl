# Copyright (c) 2023-present Matt Kaes and contributors

"""Native validation runners shared by every project."""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_test.bzl", "cc_test")

def test(name, srcs = [], deps = [], **kwargs):
    """Declare a cc_test using Toolchain's unit test runner.

    Args:
        name: Test target name.
        srcs: Source labels containing the tests and their supporting code.
        deps: C++ dependencies required by the tests.
        **kwargs: Additional attributes forwarded to cc_test.
    """
    cc_test(
        name = name,
        srcs = srcs,
        deps = deps + [Label("//source/toolchain/validation:test")],
        **kwargs
    )

def benchmark(name, srcs = [], deps = [], **kwargs):
    """Declare a testonly binary using Toolchain's benchmark runner.

    Args:
        name: Benchmark executable target name.
        srcs: Source labels containing the benchmarks and their supporting code.
        deps: C++ dependencies required by the benchmarks.
        **kwargs: Additional attributes forwarded to cc_binary.
    """
    cc_binary(
        name = name,
        testonly = True,
        srcs = srcs,
        deps = deps + [Label("//source/toolchain/validation:benchmark")],
        **kwargs
    )
