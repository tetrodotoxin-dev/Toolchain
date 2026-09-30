# Copyright (c) 2023-present Matt Kaes and contributors

"""Compile static libraries and explicitly exported shared libraries."""

load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")

LINUX = Label("//:linux")
WEB = Label("//:web")
WINDOWS = Label("//:windows")

def static_library(name, deps = [], **kwargs):
    """Compile a static library with Toolchain's export annotation available.

    Args:
        name: Static library target name.
        deps: C++ dependencies required by the library.
        **kwargs: Additional cc_library attributes.
    """
    cc_library(
        name = name,
        deps = deps + [Label("//source:headers")],
        linkstatic = True,
        **kwargs
    )

def shared_library(name, deps = [], shared_lib_name = None, user_link_flags = [], features = [], tags = [], **kwargs):
    """Link static implementations into a shared library with explicit exports.

    Providers mark exported definitions with TOOLCHAIN_EXPORT. The compiler
    emits the Windows export directives, so this rule needs no symbol scanner
    or authored DEF file. Other symbols retain their compiled visibility.

    Args:
        name: Shared library target name and default binary stem.
        deps: Static implementation targets linked into the shared library.
        shared_lib_name: Optional binary filename, including its extension.
        user_link_flags: Additional linker arguments.
        features: Additional C++ toolchain features.
        tags: Additional Bazel target tags.
        **kwargs: Additional cc_shared_library attributes.
    """
    cc_shared_library(
        name = name,
        deps = deps,
        shared_lib_name = shared_lib_name or select({WINDOWS: name + ".dll", "//conditions:default": "lib" + name + ".so"}),
        tags = tags + ["__DONT_DEPEND_ON_DEF_PARSER__"],
        features = features + ["-windows_export_all_symbols"],
        user_link_flags = select({LINUX: ["-Wl,-z,defs", "-Wl,-rpath,$ORIGIN"], "//conditions:default": []}) + user_link_flags,
        **kwargs
    )
