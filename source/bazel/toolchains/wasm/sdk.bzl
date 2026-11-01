# Copyright (c) 2023-present Matt Kaes and contributors

"""Expose downloaded Emscripten and Node executables with their input files."""

WasmToolsInfo = provider(fields = {"tools": "Tool names mapped to declared executable Files."})

def _files(ctx):
    tools = {}
    for target, name in ctx.attr.tools.items():
        files = target[DefaultInfo].files.to_list()
        if len(files) != 1:
            fail("Web tool " + name + " must supply exactly one executable file")
        tools[name] = files[0]
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        WasmToolsInfo(tools = tools),
    ]

wasm_tools = rule(
    implementation = _files,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "tools": attr.label_keyed_string_dict(allow_files = True, mandatory = True),
    },
)
