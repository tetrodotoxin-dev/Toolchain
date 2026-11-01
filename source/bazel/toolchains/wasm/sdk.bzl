# Copyright (c) 2023-present Matt Kaes and contributors

"""Expose downloaded Emscripten and Node executables with their input files."""

WasmToolsInfo = provider(fields = {"paths": "Tool names mapped to absolute host executable paths."})

def _files(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        WasmToolsInfo(paths = ctx.attr.paths),
    ]

wasm_tools = rule(
    implementation = _files,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "paths": attr.string_dict(mandatory = True),
    },
)
