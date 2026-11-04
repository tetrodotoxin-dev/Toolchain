# Copyright (c) 2023-present Matt Kaes and contributors

"""Normalize downloaded SDK files with the declared Python distribution."""

def _python(ctx):
    return ctx.path(Label("@host_python//:BUILD.bazel")).dirname.get_child(
        "python.exe" if "windows" in ctx.os.name.lower() else "python",
    )

def copy_tool(ctx, source, destination):
    """Materialize executable aliases so cached trees retain no fetch-root links."""
    normalize_sdk(ctx, "copy", [str(ctx.path(source)), str(ctx.path(destination))])

def normalize_sdk(ctx, target, arguments = []):
    """Keep normalized SDK contents independent of host LLVM settings."""
    script = ctx.path(Label("//source:sdk/normalize.py"))
    ctx.watch(script)

    result = ctx.execute([_python(ctx), "-I", "-B", script, target] + arguments)
    if result.return_code:
        fail(result.stderr)
