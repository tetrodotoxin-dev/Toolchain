"""Analysis check for validation-specific runtime artifacts."""

def _paths(target):
    return {
        file.short_path: True
        for file in target[DefaultInfo].default_runfiles.files.to_list()
    }

def _validation_data_impl(ctx):
    tests = _paths(ctx.attr.tests)
    benchmarks = _paths(ctx.attr.benchmarks)
    test_data = ctx.file.test_data.short_path
    benchmark_data = ctx.file.benchmark_data.short_path

    if test_data not in tests:
        fail("Tests are missing their declared runtime artifact: " + test_data)
    if benchmark_data in tests:
        fail("Tests contain benchmark-only runtime data: " + benchmark_data)
    if benchmark_data not in benchmarks:
        fail("Benchmarks are missing their declared runtime artifact: " + benchmark_data)
    if test_data in benchmarks:
        fail("Benchmarks contain test-only runtime data: " + test_data)

    executable = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(executable, "#!/bin/sh\nexit 0\n", is_executable = True)
    return DefaultInfo(executable = executable)

validation_data_test = rule(
    implementation = _validation_data_impl,
    test = True,
    attrs = {
        "benchmarks": attr.label(mandatory = True),
        "benchmark_data": attr.label(allow_single_file = True, mandatory = True),
        "tests": attr.label(mandatory = True),
        "test_data": attr.label(allow_single_file = True, mandatory = True),
    },
)
