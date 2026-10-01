# Copyright (c) 2023-present Matt Kaes and contributors

"""Install the shared VS Code configuration for native validation."""

load("@host_tools//:settings.bzl", "HOST_SYSTEM")

def _install(ctx):
    """Prepare the shared JSON files and a host command that copies them.

    Args:
        ctx: Rule context containing the shared editor files.

    Returns:
        DefaultInfo for the installer and its adjacent configuration files.
    """
    directory = ctx.label.name + ".files"
    outputs = []
    for source in ctx.files._configuration:
        output = ctx.actions.declare_file(directory + "/" + source.basename)
        ctx.actions.expand_template(template = source, output = output, substitutions = {})
        outputs.append(output)

    if HOST_SYSTEM == "windows":
        executable = ctx.actions.declare_file(ctx.label.name + ".cmd")
        command = '@echo off\r\nif not exist "%BUILD_WORKSPACE_DIRECTORY%\\.vscode" mkdir "%BUILD_WORKSPACE_DIRECTORY%\\.vscode"\r\n'
        for source in outputs:
            command += 'copy /Y "%%~dp0%s\\%s" "%%BUILD_WORKSPACE_DIRECTORY%%\\.vscode\\%s" >nul\r\nif errorlevel 1 exit /b 1\r\n' % (directory.replace("%", "%%"), source.basename, source.basename)
    else:
        executable = ctx.actions.declare_file(ctx.label.name + ".sh")
        command = '#!/bin/sh\nset -eu\ndestination="$BUILD_WORKSPACE_DIRECTORY/.vscode"\nmkdir -p "$destination"\n'
        command += 'source_directory="$(dirname "$0")"/\'%s\'\n' % directory.replace("'", "'\\''")

        # Bazel outputs are read only, including copies from an earlier install.
        command += 'cp -f "$source_directory/"*.json "$destination/"\n'
    ctx.actions.write(executable, command, is_executable = True)
    outputs.append(executable)
    return [DefaultInfo(executable = executable, files = depset(outputs), runfiles = ctx.runfiles(files = outputs))]

_vscode = rule(
    implementation = _install,
    executable = True,
    attrs = {
        "_configuration": attr.label_list(default = [
            Label("//source/vscode:c_cpp_properties.json"),
            Label("//source/vscode:launch.json"),
            Label("//source/vscode:tasks.json"),
            Label("//source/vscode:extensions.json"),
        ], allow_files = True),
    },
)

def vscode(name):
    """Declare `bazel run //:vscode` to populate the repository's .vscode folder.

    The shared files expect //:build, //validation:unit_tests and
    //validation:benchmarks. Debug and Release profiles run Build All in the
    selected mode, then launch either Unit Tests or Benchmarks under CodeLLDB.
    IntelliSense uses source/ for the project's public include paths and
    Bazel's generated include trees under .bin/bin for dependencies.
    Repeating the command replaces these shared configuration files with the
    Toolchain versions. Keep .vscode ignored in the consuming repository.

    Args:
        name: Installer target name, conventionally vscode at the project root.
    """
    _vscode(name = name)
