# Copyright (c) 2023-present Matt Kaes and contributors

"""Archive the clean Git commit that defines one project release."""

load("@host_tools//:settings.bzl", "HOST_SYSTEM", "PYTHON")

def _snapshot_impl(ctx):
    """Generate the host launcher for the repository snapshot command."""
    driver = ctx.actions.declare_file(ctx.label.name + ".py")
    ctx.actions.expand_template(
        template = ctx.file._driver,
        output = driver,
        substitutions = {
            "__PROJECT__": repr(ctx.attr.project),
            "__VERSION__": repr(ctx.attr.version),
        },
        is_executable = True,
    )
    if HOST_SYSTEM == "windows":
        executable = ctx.actions.declare_file(ctx.label.name + ".cmd")
        command = '@echo off\r\n"%s" "%%~dp0%s" %%*\r\n' % (PYTHON, driver.basename)
    else:
        executable = ctx.actions.declare_file(ctx.label.name + ".sh")
        command = "#!/bin/sh\nset -eu\ndirectory=${0%%/*}\nexec '%s' \"$directory/%s\" \"$@\"\n" % (PYTHON.replace("'", "'\\''"), driver.basename)
    ctx.actions.write(executable, command, is_executable = True)
    return [DefaultInfo(
        executable = executable,
        files = depset([executable]),
        runfiles = ctx.runfiles(files = [executable, driver]),
    )]

_snapshot = rule(
    implementation = _snapshot_impl,
    executable = True,
    attrs = {
        "project": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "_driver": attr.label(
            default = Label("//source/bazel:rules/snapshot.py.tpl"),
            allow_single_file = True,
        ),
    },
)

def snapshot():
    """Declare `bazel run :snapshot` for the repository's committed state."""
    if native.package_name():
        fail("snapshot must be declared from the repository root BUILD file")
    _snapshot(
        name = "snapshot",
        project = native.module_name(),
        version = native.module_version(),
    )
