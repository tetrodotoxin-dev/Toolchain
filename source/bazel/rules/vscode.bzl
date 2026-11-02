# Copyright (c) 2023-present Matt Kaes and contributors

"""Install the shared VS Code configuration for native validation."""

load("@host_tools//:settings.bzl", "CLANG_FORMAT", "HOST_SYSTEM")

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
        if source.basename == "settings.json":
            ctx.actions.expand_template(
                template = source,
                output = output,
                substitutions = {"__CLANG_FORMAT__": json.encode(CLANG_FORMAT)[1:-1]},
            )
        else:
            ctx.actions.symlink(output = output, target_file = source)
        outputs.append(output)

    executable = ctx.actions.declare_file(ctx.label.name + (".cmd" if HOST_SYSTEM == "windows" else ".sh"))
    ctx.actions.expand_template(
        template = ctx.file._launcher,
        output = executable,
        substitutions = {},
        is_executable = True,
    )
    outputs.append(executable)
    runfiles = ctx.runfiles(files = outputs)
    runfiles = runfiles.merge(ctx.attr.formatter[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = executable, files = depset(outputs), runfiles = runfiles)]

_vscode = rule(
    implementation = _install,
    executable = True,
    attrs = {
        "_launcher": attr.label(
            default = Label("//source/bazel:rules/vscode.cmd" if HOST_SYSTEM == "windows" else "//source/bazel:rules/vscode.sh"),
            allow_single_file = True,
        ),
        "_configuration": attr.label_list(default = [
            Label("//source/vscode:c_cpp_properties.json"),
            Label("//source/vscode:settings.json"),
            Label("//source/vscode:launch.json"),
            Label("//source/vscode:tasks.json"),
            Label("//source/vscode:extensions.json"),
        ], allow_files = True),
        "formatter": attr.label(executable = True, cfg = "target", mandatory = True),
    },
)

def vscode(name = "vscode"):
    """Declare `bazel run //:vscode` to populate the repository's .vscode folder.

    The shared files run //:tests, //:benchmarks and
    //validation/integration:integration.
    Debug and Release profiles build all targets in the selected mode, then
    launch either executable under CodeLLDB.
    Formatting tasks use //:format so MODULE.bazel supplies SDK include order.
    IntelliSense uses source/ for the project's public include paths and
    Bazel's generated include trees under .bin/bin for dependencies.
    Repeating the command replaces these shared configuration files with the
    Toolchain versions. Keep .vscode ignored in the consuming repository.

    Args:
        name: Installer target name, defaulting to vscode at the project root.
    """
    if native.package_name():
        fail("vscode must be declared from the repository root BUILD file")
    _vscode(name = name, formatter = ":format")
