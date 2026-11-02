# Copyright (c) 2023-present Matt Kaes and contributors

"""Build ordinary check programs and their portable invocation inventory."""

load("@rules_python//python:py_binary.bzl", "py_binary")

def check(name, args = [], data = [], **kwargs):
    """Keep each program's arguments shared by Bazel run and direct execution."""
    py_binary(name = name, args = args, data = data, testonly = True, **kwargs)
    return struct(name = name, script = ":" + kwargs.get("main", kwargs["srcs"][0]), args = args, data = data)

def _commands_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    commands = {}
    for name, arguments in ctx.attr.commands.items():
        commands[name] = [ctx.expand_location(argument, targets = ctx.attr.data) for argument in json.decode(arguments)]
    ctx.actions.write(output, json.encode(commands))
    files = [output] + ctx.files.data
    for target in ctx.attr.data:
        manifest = target[DefaultInfo].files_to_run.runfiles_manifest
        if manifest:
            files.append(manifest)
    return [DefaultInfo(
        files = depset([output]),
        runfiles = ctx.runfiles(files = files).merge_all([target[DefaultInfo].default_runfiles for target in ctx.attr.data]),
    )]

_commands = rule(
    implementation = _commands_impl,
    attrs = {
        "commands": attr.string_dict(mandatory = True),
        "data": attr.label_list(allow_files = True),
    },
)

def runner(name, checks, binaries = [], data = []):
    """Declare a process runner with its programs, inputs and argument inventory."""
    commands = {check.name: json.encode([native.package_name() + "/" + check.script[1:]] + check.args) for check in checks}
    commands.update({binary.split(":")[-1]: json.encode([".bin/bin/$(rootpath " + binary + ")"]) for binary in binaries})
    _commands(
        name = name + "_commands",
        commands = commands,
        data = list({label: True for check in checks for label in [check.script] + check.data}) + binaries,
        testonly = True,
        tags = ["manual"],
    )
    py_binary(
        name = name,
        srcs = ["runner.py"],
        main = "runner.py",
        args = [".bin/bin/" + native.package_name() + "/" + name + "_commands.json"],
        data = [":" + name + "_commands"] + data,
        testonly = True,
        tags = ["manual"],
    )
