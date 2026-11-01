# Copyright (c) 2023-present Matt Kaes and contributors

"""Expose the downloaded SDK and its host executable directory."""

WasmSdkInfo = provider(fields = {"root": "Absolute host path to the downloaded SDK."})

def _files(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        WasmSdkInfo(root = ctx.attr.root),
    ]

wasm_sdk_files = rule(
    implementation = _files,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "root": attr.string(mandatory = True),
    },
)
