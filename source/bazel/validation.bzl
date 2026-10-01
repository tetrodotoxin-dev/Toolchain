# Copyright (c) 2023-present Matt Kaes and contributors

"""Native validation runners shared by every project."""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")

def tests(name = "tests", srcs = [], deps = [], **kwargs):
    """Declare a standalone binary using Toolchain's test runner.

    Fixture paths are relative to the working directory. Repositories use
    `run --run_in_cwd` so Bazel and direct execution share that directory.

    Args:
        name: Executable target name, defaulting to tests.
        srcs: Source labels containing the tests and their supporting code.
        deps: C++ dependencies required by the tests.
        **kwargs: Additional attributes forwarded to cc_binary.
    """
    cc_binary(
        name = name,
        testonly = True,
        srcs = srcs,
        deps = deps + [Label("//source/toolchain/validation:test")],
        **kwargs
    )

def benchmarks(name = "benchmarks", srcs = [], deps = [], **kwargs):
    """Declare a testonly binary using Toolchain's benchmark runner.

    Args:
        name: Executable target name, defaulting to benchmarks.
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
