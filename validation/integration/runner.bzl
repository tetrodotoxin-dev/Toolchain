# Copyright (c) 2023-present Matt Kaes and contributors

"""Build ordinary check programs and their portable invocation inventory."""

load("@rules_python//python:py_binary.bzl", "py_binary")

def check(name, args = [], data = [], **kwargs):
    """Keep each program's arguments shared by Bazel run and direct execution."""
    py_binary(name = name, args = args, data = data, testonly = True, **kwargs)
    return struct(label = ":" + name, args = args, data = data)

def _runfile(ctx, file):
    path = file.short_path
    return path[3:] if path.startswith("../") else ctx.workspace_name + "/" + path

def _commands_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    commands = {}
    files = [output]
    runtime = []
    for program, arguments in ctx.attr.commands.items():
        executable = program[DefaultInfo].files_to_run.executable
        commands[program.label.name] = [_runfile(ctx, executable)] + [ctx.expand_location(argument, targets = ctx.attr.data) for argument in json.decode(arguments)]
        files.append(executable)
        runtime.append(program[DefaultInfo].default_runfiles)
    ctx.actions.write(output, json.encode(commands))
    return [DefaultInfo(files = depset([output]), runfiles = ctx.runfiles(files = files).merge_all(runtime))]

_commands = rule(
    implementation = _commands_impl,
    attrs = {
        "commands": attr.label_keyed_string_dict(mandatory = True),
        "data": attr.label_list(allow_files = True),
    },
)

def runner(name, checks, binaries = [], data = []):
    """Declare a process runner with its programs, inputs and argument inventory."""
    commands = {check.label: json.encode(check.args) for check in checks}
    commands.update({binary: "[]" for binary in binaries})
    _commands(
        name = name + "_commands",
        commands = commands,
        data = list({label: True for check in checks for label in check.data}),
        testonly = True,
        tags = ["manual"],
    )
    py_binary(
        name = name,
        srcs = ["runner.py"],
        main = "runner.py",
        args = ["$(rlocationpath :" + name + "_commands)"],
        data = [":" + name + "_commands"] + data,
        deps = ["@rules_python//python/runfiles"],
        testonly = True,
        tags = ["manual"],
    )
