# Copyright (c) 2023-present Matt Kaes and contributors

"""Canonical compiled validation runners shared by every project.

Repositories collect their native and process-boundary checks under
//validation:integration. Tests and benchmarks remain runnable programs because
their reports and filters are part of the developer interface.
"""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")

_SOURCE_EXTENSIONS = ["c", "cpp", "h", "hpp"]

def _sources(directory):
    if native.package_name() != "validation":
        fail(directory + " must be declared from //validation:BUILD")
    sources = native.glob(
        [directory + "/**/*." + extension for extension in _SOURCE_EXTENSIONS],
        allow_empty = True,
    )
    if not sources:
        fail("validation/" + directory + " must contain validation sources")
    return sources

def tests(deps = [], **kwargs):
    """Declare //validation:tests from validation/tests sources.

    Fixture paths are relative to the working directory. Repositories use
    `run --run_in_cwd` so Bazel and direct execution share that directory.

    Args:
        deps: C++ dependencies required by the tests.
        **kwargs: Additional attributes forwarded to cc_binary.
    """
    if "name" in kwargs or "srcs" in kwargs:
        fail("tests owns the //validation:tests name and validation/tests source set")
    cc_binary(
        name = "tests",
        testonly = True,
        srcs = _sources("tests"),
        deps = deps + [Label("//source/toolchain/validation:test")],
        **kwargs
    )

def benchmarks(deps = [], **kwargs):
    """Declare //validation:benchmarks from validation/benchmarks sources.

    Args:
        deps: C++ dependencies required by the benchmarks.
        **kwargs: Additional attributes forwarded to cc_binary.
    """
    if "name" in kwargs or "srcs" in kwargs:
        fail("benchmarks owns the //validation:benchmarks name and validation/benchmarks source set")
    cc_binary(
        name = "benchmarks",
        testonly = True,
        srcs = _sources("benchmarks"),
        deps = deps + [Label("//source/toolchain/validation:benchmark")],
        **kwargs
    )
