# Copyright (c) 2023-present Matt Kaes and contributors

"""Expose Toolchain's pinned source formatter at the repository root."""

load("@host_tools//:settings.bzl", "CLANG_FORMAT", "HOST_SYSTEM", "PYTHON")
load(":rules/python.bzl", "python_launcher")

def _format_impl(ctx):
    """Generate one host launcher, driver and formatter configuration.

    Args:
        ctx: Rule context containing Toolchain's driver and style configuration.

    Returns:
        DefaultInfo for the runnable formatter and its adjacent inputs.
    """
    driver = ctx.actions.declare_file(ctx.label.name + ".py")
    policy = ctx.actions.declare_file("format_policy.py")
    comment_quality = ctx.actions.declare_file("comment_quality.py")
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
    ctx.actions.symlink(output = policy, target_file = ctx.file._policy)
    ctx.actions.symlink(output = comment_quality, target_file = ctx.file._comment_quality)
    ctx.actions.symlink(output = configuration, target_file = ctx.file._configuration)

    executable = python_launcher(ctx, driver)
    files = [executable, driver, policy, comment_quality, configuration]
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
            default = Label("//source/bazel:rules/.clang-format"),
            allow_single_file = True,
        ),
        "_comment_quality": attr.label(
            default = Label("//source/bazel:rules/comment_quality.py"),
            allow_single_file = True,
        ),
        "_driver": attr.label(
            default = Label("//source/bazel:rules/format.py.tpl"),
            allow_single_file = True,
        ),
        "_launcher": attr.label(
            default = Label("//source/bazel:rules/python.cmd.tpl" if HOST_SYSTEM == "windows" else "//source/bazel:rules/python.sh.tpl"),
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

    A call without arguments formats every C and C++ file under the standard
    source directories. Exact file arguments select a review-sized mutable set,
    while --all states the complete selection explicitly. Every run formats
    the selection and enforces the SDK::Module import shape. Source scans print
    aggregate comment quality status; warnings and rejections fail the command.
    Each explicit constructor carries its own comment naming the conversion
    boundary it protects. Runs generate the repository's include buckets from
    MODULE.bazel. Source validation verifies that generated
    configuration together with namespace structure, complete declarations,
    state ownership, preprocessor boundaries, multiline brace boundaries and
    lexical paragraph order in the selected sources.
    """
    if native.package_name():
        fail("format must be declared from the repository root BUILD file")
    _format(name = "format")
