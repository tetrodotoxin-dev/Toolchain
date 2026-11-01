# Copyright (c) 2023-present Matt Kaes and contributors

"""Normalize downloaded SDK files with the declared Python distribution."""

def _python(ctx):
    return ctx.path(Label("@host_python//:BUILD.bazel")).dirname.get_child(
        "python.exe" if "windows" in ctx.os.name.lower() else "python",
    )

def copy_tool(ctx, source, destination):
    """Materialize executable aliases so cached trees retain no fetch-root links."""
    result = ctx.execute([
        _python(ctx), "-I", "-B", "-c",
        "import shutil, sys; shutil.copy2(sys.argv[1], sys.argv[2])",
        ctx.path(source), ctx.path(destination),
    ])
    if result.return_code:
        fail(result.stderr)

def normalize_sdk(ctx, target, arguments = []):
    """Keep normalized SDK contents independent of host LLVM settings."""
    ctx.file("normalize.py", ctx.read(Label("//source:sdk/normalize.py")))
    result = ctx.execute([_python(ctx), "-I", "-B", ctx.path("normalize.py"), target] + arguments)
    if result.return_code:
        fail(result.stderr)
