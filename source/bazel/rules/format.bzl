# Copyright (c) 2023-present Matt Kaes and contributors

"""Expose Toolchain's pinned source formatter at the repository root."""

load("@host_tools//:settings.bzl", "CLANG_FORMAT", "HOST_SYSTEM", "PYTHON")

def _format_impl(ctx):
    """Generate one host launcher, driver and formatter configuration.

    Args:
        ctx: Rule context containing Toolchain's driver and style template.

    Returns:
        DefaultInfo for the runnable formatter and its adjacent inputs.
    """
    driver = ctx.actions.declare_file(ctx.label.name + ".py")
    policy = ctx.actions.declare_file("format_policy.py")
    configuration = ctx.actions.declare_file(ctx.label.name + ".clang-format")
    ctx.actions.expand_template(
        template = ctx.file._driver,
        output = driver,
        substitutions = {
            "__PYTHON__": PYTHON,
            "__CLANG_FORMAT__": repr(CLANG_FORMAT),
            "__CONFIGURATION__": configuration.basename,
        },
        is_executable = True,
    )
    ctx.actions.expand_template(
        template = ctx.file._policy,
        output = policy,
        substitutions = {},
    )
    ctx.actions.expand_template(
        template = ctx.file._configuration,
        output = configuration,
        substitutions = {},
    )

    if HOST_SYSTEM == "windows":
        executable = ctx.actions.declare_file(ctx.label.name + ".cmd")
        command = '@echo off\r\n"%s" "%%~dp0%s" %%*\r\n' % (PYTHON, driver.basename)
    else:
        executable = ctx.actions.declare_file(ctx.label.name + ".sh")
        command = "#!/bin/sh\nset -eu\ndirectory=${0%%/*}\nexec '%s' \"$directory/%s\" \"$@\"\n" % (PYTHON.replace("'", "'\\''"), driver.basename)
    ctx.actions.write(executable, command, is_executable = True)
    files = [executable, driver, policy, configuration]
    return [DefaultInfo(
        executable = executable,
        files = depset([executable]),
        runfiles = ctx.runfiles(files = files),
    )]

_format = rule(
    implementation = _format_impl,
    executable = True,
    attrs = {
        "_configuration": attr.label(
            default = Label("//source/bazel:rules/.clang-format.tpl"),
            allow_single_file = True,
        ),
        "_driver": attr.label(
            default = Label("//source/bazel:rules/format.py.tpl"),
            allow_single_file = True,
        ),
        "_policy": attr.label(
            default = Label("//source/bazel:rules/source_policy.py"),
            allow_single_file = True,
        ),
    },
)

def format():
    """Declare the canonical //:format target from the repository root.

    Exact file arguments select a review-sized mutable set. --all explicitly
    selects every C and C++ file under the standard source directories. --check
    validates the selected files, or the complete standard tree when used by
    itself, and enforces the SDK::Module import shape. Mutable runs generate the
    repository's include buckets from MODULE.bazel; checks verify that generated
    configuration together with namespace structure, comment vocabulary,
    complete declarations, state ownership, preprocessor boundaries and lexical
    paragraph order in the selected sources.
    """
    if native.package_name():
        fail("format must be declared from the repository root BUILD file")
    _format(name = "format")
