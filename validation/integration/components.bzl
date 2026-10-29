# Copyright (c) 2023-present Matt Kaes and contributors

"""Check declared component headers independently of filesystem sandboxing."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _component_headers_impl(ctx):
    component = ctx.attr.component
    headers = component[CcInfo].compilation_context.headers.to_list()
    for header in ctx.files.required:
        if header not in headers:
            fail("Component is missing a declared dependency header: " + header.short_path)
    for header in ctx.files.excluded:
        if header in headers:
            fail("Component exposes an unrelated sibling header: " + header.short_path)
    return [component[CcInfo], component[DefaultInfo]]

component_headers = rule(
    implementation = _component_headers_impl,
    attrs = {
        "component": attr.label(mandatory = True, providers = [CcInfo]),
        "required": attr.label_list(allow_files = True),
        "excluded": attr.label_list(allow_files = True),
    },
)
