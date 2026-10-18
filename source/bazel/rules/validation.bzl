# Copyright (c) 2023-present Matt Kaes and contributors

"""Canonical compiled validation runners shared by every project.

Repositories collect their native checks under validation/tests and
validation/benchmarks. Tests and benchmarks remain runnable programs because
their reports and filters are part of the developer interface.
"""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")

_SOURCE_EXTENSIONS = ["c", "cpp", "h", "hpp"]

def _web_runner_impl(ctx):
    """Generate one host launcher for an Emscripten validation program."""
    executable = ctx.actions.declare_file(ctx.label.name)
    binary = ctx.file.binary
    node = ctx.file.node
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = executable,
        substitutions = {
            "__NODE__": node.short_path,
            "__PROGRAM__": binary.short_path,
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [binary, node])
    runfiles = runfiles.merge(ctx.attr.binary[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.attr.node[DefaultInfo].default_runfiles)
    return DefaultInfo(executable = executable, runfiles = runfiles)

_web_runner = rule(
    implementation = _web_runner_impl,
    executable = True,
    attrs = {
        "binary": attr.label(mandatory = True, allow_single_file = True),
        "node": attr.label(mandatory = True, allow_single_file = True),
        "_template": attr.label(
            default = Label("//source/bazel:rules/web_runner.sh"),
            allow_single_file = True,
        ),
    },
)

def _sources(directory):
    if native.package_name():
        fail(directory + " must be declared from the repository root BUILD file")
    sources = native.glob(
        ["validation/" + directory + "/**/*." + extension for extension in _SOURCE_EXTENSIONS],
        allow_empty = True,
    )
    if not sources:
        fail("validation/" + directory + " must contain validation sources")
    return sources

def _tests(deps, data):
    cc_binary(
        name = "tests_binary",
        testonly = True,
        srcs = _sources("tests"),
        deps = deps + [Label("//source/toolchain/validation:test")],
        data = data,
    )
    _select_runner("tests")

def _benchmarks(deps, data):
    cc_binary(
        name = "benchmarks_binary",
        testonly = True,
        srcs = _sources("benchmarks"),
        deps = deps + [Label("//source/toolchain/validation:benchmark")],
        data = data,
    )
    _select_runner("benchmarks")

def _select_runner(name):
    """Expose native programs directly and host standalone Web programs in Node.

    Args:
        name: Public validation target and its private binary prefix.
    """
    binary = name + "_binary"
    runner = name + "_web_runner"
    node = Label("@emscripten_node//:node")
    _web_runner(
        name = runner,
        testonly = True,
        binary = ":" + binary,
        node = node,
    )
    native.alias(
        name = name,
        actual = select({
            Label("@tetro_toolchain//:web_runner"): ":" + runner,
            "//conditions:default": ":" + binary,
        }),
    )

def validation(deps = None, test_deps = [], benchmark_deps = []):
    """Declare the canonical validation programs from the repository root.

    The project library supplies the common dependency by default. Tests and
    benchmarks can add the distinct dependencies required by their workloads.
    Both programs receive the artifacts under validation/data. Fixture paths
    remain relative to the working directory so Bazel and direct execution
    share one data model.

    Args:
        deps: Dependencies shared by both programs, defaulting to the root
            target named by the Bazel module.
        test_deps: Additional dependencies required only by tests.
        benchmark_deps: Additional dependencies required only by benchmarks.
    """
    if native.package_name():
        fail("validation must be declared from the repository root BUILD file")
    common = ["//:" + native.module_name()] if deps == None else deps
    data = native.glob(["validation/data/**"], allow_empty = True)
    _tests(common + test_deps, data)
    _benchmarks(common + benchmark_deps, data)
