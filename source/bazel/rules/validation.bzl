# Copyright (c) 2023-present Matt Kaes and contributors

"""Canonical compiled validation runners shared by every project.

Repositories collect their native checks under validation/tests and
validation/benchmarks. Tests and benchmarks remain runnable programs because
their reports and filters are part of the developer interface.
"""

load("@host_tools//:settings.bzl", "HOST_SYSTEM")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")

_SOURCE_EXTENSIONS = ["c", "cpp", "h", "hpp"]
_WASM_RUNNER_PLATFORM = str(Label("//:wasm32_runner"))
_FEATURES = "//command_line_option:features"

# Runnable Web targets compile their private binary with Emscripten's Node
# runtime while ordinary Web binaries retain the hosted SDK platform. This
# target transition lets `bazel run :tests --config=web` select an executable
# program without changing `:tests_binary` or SDK compilation.
def _wasm_runner(settings, attr):
    features = [feature for feature in settings[_FEATURES] if feature != "wasm_threads"]
    if attr.threads:
        features.append("wasm_threads")
    return {
        "//command_line_option:platforms": [_WASM_RUNNER_PLATFORM],
        _FEATURES: features,
    }

_wasm_runner_transition = transition(
    implementation = _wasm_runner,
    inputs = [_FEATURES],
    outputs = ["//command_line_option:platforms", _FEATURES],
)

def _runfile(ctx, file):
    """Use the same canonical runfiles key in both host launchers."""
    path = file.short_path
    return path[3:] if path.startswith("../") else ctx.workspace_name + "/" + path

def _web_runner_impl(ctx):
    """Generate one host launcher for an Emscripten validation program."""
    executable = ctx.actions.declare_file(ctx.label.name + (".cmd" if HOST_SYSTEM == "windows" else ""))
    binary = ctx.file.binary
    binary_target = ctx.attr.binary[0]
    node = ctx.file.node
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = executable,
        substitutions = {
            "__NODE__": _runfile(ctx, node),
            "__PROGRAM__": _runfile(ctx, binary),
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [binary, node])
    runfiles = runfiles.merge(binary_target[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.attr.node[DefaultInfo].default_runfiles)
    return DefaultInfo(executable = executable, runfiles = runfiles)

_web_runner = rule(
    implementation = _web_runner_impl,
    executable = True,
    attrs = {
        "binary": attr.label(
            mandatory = True,
            allow_single_file = True,
            cfg = _wasm_runner_transition,
        ),
        "node": attr.label(mandatory = True, allow_single_file = True),
        "threads": attr.bool(default = True),
        "_template": attr.label(
            default = Label("//source/bazel:rules/web_runner.cmd.tpl" if HOST_SYSTEM == "windows" else "//source/bazel:rules/web_runner.sh"),
            allow_single_file = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
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

def _program(name, runtime, deps, web_deps, web_threads, data):
    """Declare matching native and Web programs and select their public runner."""
    sources = _sources(name)
    cc_binary(
        name = name + "_binary",
        testonly = True,
        srcs = sources,
        deps = deps + [runtime],
        data = data,
    )
    cc_binary(
        name = name + "_web_binary",
        tags = ["manual"],
        testonly = True,
        srcs = sources,
        deps = web_deps + [runtime],
        data = data,
    )
    binary = name + "_binary"
    runner = name + "_web_runner"
    node = Label("@emscripten_node//:node")
    _web_runner(
        name = runner,
        tags = ["manual"],
        testonly = True,
        binary = ":" + name + "_web_binary",
        node = node,
        threads = web_threads,
    )
    native.alias(
        name = name,
        actual = select({
            Label("@tetro_toolchain//:web"): ":" + runner,
            "//conditions:default": ":" + binary,
        }),
    )

def validation(
        deps = None,
        web_deps = None,
        test_deps = [],
        web_test_deps = None,
        benchmark_deps = [],
        web_benchmark_deps = None,
        web_threads = True,
        test_data = [],
        benchmark_data = []):
    """Declare the canonical validation programs from the repository root.

    The project library supplies the common dependency by default. Tests and
    benchmarks can add the distinct dependencies and runtime artifacts required
    by their workloads. Both programs receive the artifacts under
    validation/data. Fixture paths remain relative to the working directory so
    Bazel and direct execution share one data model.

    Args:
        deps: Dependencies shared by both programs, defaulting to the root
            target named by the Bazel module.
        web_deps: Dependencies shared by Web programs, defaulting to the
            packaged static runtime when deps is omitted and otherwise to deps.
        test_deps: Additional dependencies required only by tests.
        web_test_deps: Additional dependencies for Web tests, defaulting to
            test_deps.
        benchmark_deps: Additional dependencies required only by benchmarks.
        web_benchmark_deps: Additional dependencies for Web benchmarks,
            defaulting to benchmark_deps.
        web_threads: Enables Emscripten threads for Web tests and benchmarks.
        test_data: Runtime artifacts required only by tests.
        benchmark_data: Runtime artifacts required only by benchmarks.
    """
    if native.package_name():
        fail("validation must be declared from the repository root BUILD file")
    if deps == None:
        common = ["//:" + native.module_name()]
        web_common = ["//:_validation_static"] if web_deps == None else web_deps
    else:
        common = deps
        web_common = deps if web_deps == None else web_deps

    web_tests = test_deps if web_test_deps == None else web_test_deps
    web_benchmarks = benchmark_deps if web_benchmark_deps == None else web_benchmark_deps
    data = native.glob(["validation/data/**"], allow_empty = True)
    _program(
        name = "tests",
        runtime = Label("//source/toolchain/validation:test"),
        deps = common + test_deps,
        web_deps = web_common + web_tests,
        web_threads = web_threads,
        data = data + test_data,
    )
    _program(
        name = "benchmarks",
        runtime = Label("//source/toolchain/validation:benchmark"),
        deps = common + benchmark_deps,
        web_deps = web_common + web_benchmarks,
        web_threads = web_threads,
        data = data + benchmark_data,
    )
