# Copyright (c) 2023-present Matt Kaes and contributors

"""Install the shared Bazel and VS Code configuration at the project root."""

load("@host_tools//:settings.bzl", "HOST_SYSTEM")

def _install(ctx):
    """Prepare the shared configuration and its host installer.

    Args:
        ctx: Rule context containing the shared Bazel and editor files.

    Returns:
        DefaultInfo for the installer and its adjacent configuration files.
    """
    directory = ctx.label.name + ".files"
    outputs = []
    for source in ctx.files._configuration + [ctx.file._bazelrc]:
        output = ctx.actions.declare_file(directory + "/" + source.basename)
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
    return [DefaultInfo(executable = executable, files = depset(outputs), runfiles = runfiles)]

_setup = rule(
    implementation = _install,
    executable = True,
    attrs = {
        "_launcher": attr.label(
            default = Label("//source/bazel:rules/setup.cmd" if HOST_SYSTEM == "windows" else "//source/bazel:rules/setup.sh"),
            allow_single_file = True,
        ),
        "_bazelrc": attr.label(default = Label("//:.bazelrc"), allow_single_file = True),
        "_configuration": attr.label_list(default = [
            Label("//source/vscode:c_cpp_properties.json"),
            Label("//source/vscode:settings.json"),
            Label("//source/vscode:launch.json"),
            Label("//source/vscode:tasks.json"),
            Label("//source/vscode:extensions.json"),
        ], allow_files = True),
    },
)

def setup(name = "setup"):
    """Declare `bazel run :setup` to install shared Bazel and editor settings.

    Toolchain owns the Bazel defaults in its root .bazelrc. Consumers install
    that file and the shared .vscode files as ignored setup outputs. Local
    overrides belong in .bazelrc.local and remain separate from these files.
    Repeating setup replaces changed configuration and retains identical files.
    The deprecated :vscode command resolves to the same installer.

    The shared files run //:tests, //:benchmarks and
    //validation/integration:integration.
    Debug and Release profiles build all targets in the selected mode, then
    launch either executable under CodeLLDB.
    Formatting tasks use //:format so MODULE.bazel supplies SDK include order.
    IntelliSense uses source/ for the project's public include paths and
    Bazel's generated include trees under .bin/bin for dependencies.

    Args:
        name: Installer target name, defaulting to setup at the project root.
    """
    if native.package_name():
        fail("setup must be declared from the repository root BUILD file")
    _setup(name = name)
    if name != "vscode":
        native.alias(
            name = "vscode",
            actual = ":" + name,
            deprecation = "Use :setup to install the Bazel and VS Code configuration.",
            tags = ["manual"],
        )
