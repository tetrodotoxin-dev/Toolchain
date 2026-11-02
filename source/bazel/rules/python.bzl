# Copyright (c) 2023-present Matt Kaes and contributors

"""Run standard-library Python tools with the pinned host interpreter."""

load("@host_tools//:settings.bzl", "HOST_SYSTEM", "PYTHON")

def python_launcher(ctx, driver, arguments = []):
    executable = ctx.actions.declare_file(ctx.label.name + (".cmd" if HOST_SYSTEM == "windows" else ".sh"))
    quoted = ['"' + value.replace("%", "%%").replace('"', '\\"') + '"' if HOST_SYSTEM == "windows" else "'" + value.replace("'", "'\\''") + "'" for value in arguments]
    ctx.actions.expand_template(
        template = ctx.file._launcher,
        output = executable,
        substitutions = {
            "__PYTHON__": PYTHON if HOST_SYSTEM == "windows" else PYTHON.replace("'", "'\\''"),
            "__DRIVER__": driver.basename,
            "__ARGUMENTS__": " ".join(quoted),
        },
        is_executable = True,
    )
    return executable

def _command(ctx):
    driver = ctx.actions.declare_file(ctx.label.name + ".py")
    ctx.actions.symlink(output = driver, target_file = ctx.file.script)
    arguments = [ctx.expand_location(value, targets = ctx.attr.data) for value in ctx.attr.arguments]
    executable = python_launcher(ctx, driver, arguments)
    runfiles = ctx.runfiles(files = [driver] + ctx.files.data)
    runfiles = runfiles.merge_all([target[DefaultInfo].default_runfiles for target in ctx.attr.data])
    return [DefaultInfo(executable = executable, runfiles = runfiles)]

python_command = rule(implementation = _command, executable = True, attrs = {
    "script": attr.label(mandatory = True, allow_single_file = True),
    "arguments": attr.string_list(),
    "data": attr.label_list(allow_files = True),
    "_launcher": attr.label(default = Label("//source/bazel:rules/python.cmd.tpl" if HOST_SYSTEM == "windows" else "//source/bazel:rules/python.sh.tpl"), allow_single_file = True),
})
