# Copyright (c) 2023-present Matt Kaes and contributors

"""Compile static libraries and explicitly exported shared libraries."""

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")

LINUX = Label("//:linux")
WEB = Label("//:web")
WINDOWS = Label("//:windows")

def _project_name(project):
    """Turn a declared project name into its EXPORTED identifier.

    Args:
        project: Explicit project name, or None for the calling Bazel module.

    Returns:
        An uppercase identifier with dots and hyphens replaced by underscores.
    """
    value = (project or native.module_name()).upper().replace("-", "_").replace(".", "_")
    if not value or value[0] in "0123456789" or any([letter not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789" for letter in value.elems()]):
        fail("project must identify the library used by EXPORTED(PROJECT)")
    return value

def static_library(name, deps = [], project = None, defines = [], **kwargs):
    """Compile a static library with Toolchain's export annotation available.

    PROJECT_STATIC=1 reaches this implementation and its consumers so both
    use ordinary declarations for EXPORTED(PROJECT).

    Args:
        name: Static library target name.
        deps: C++ dependencies required by the library.
        project: EXPORTED identifier, defaulting to the uppercase module name.
        defines: Additional definitions shared with consumers.
        **kwargs: Additional cc_library attributes.
    """
    cc_library(
        name = name,
        deps = deps + [Label("//source:headers")],
        defines = defines + [_project_name(project) + "_STATIC=1"],
        linkstatic = True,
        **kwargs
    )

def shared_library(name, srcs = [], hdrs = [], deps = [], project = None, copts = [], defines = [], local_defines = [], includes = [], linkopts = [], shared_lib_name = None, user_link_flags = [], features = [], tags = [], **kwargs):
    """Compile a shared library and expose its headers and binary to consumers.

    PROJECT_EXPORT=1 belongs to this target's source compilation. Consumers
    import EXPORTED(PROJECT) declarations with no additional definitions.
    Dependencies keep their own linkage and compilation settings.

    Args:
        name: Shared library target name and default binary stem.
        srcs: Implementation sources compiled with PROJECT_EXPORT=1.
        hdrs: Public headers available to this library and its consumers.
        deps: Libraries and headers required by the public interface.
        project: EXPORTED identifier, defaulting to the uppercase module name.
        copts: Additional options for implementation compilation.
        defines: Additional definitions shared with consumers.
        local_defines: Additional definitions private to implementation sources.
        includes: Public include directories, relative to this Bazel package.
        linkopts: Link requirements shared with consumers, such as system libraries.
        shared_lib_name: Optional binary filename, including its extension.
        user_link_flags: Linker arguments private to this shared library's link.
        features: Additional C++ toolchain features.
        tags: Additional Bazel target tags.
        **kwargs: Additional cc_shared_library attributes.
    """
    visibility = kwargs.pop("visibility", None)
    common = {key: kwargs.pop(key) for key in ["testonly", "target_compatible_with", "compatible_with"] if key in kwargs}
    kwargs.update(common)
    headers = name + "_headers"
    implementation = name + "_implementation"
    shared = name + "_shared"
    interface = name + "_interface"
    cc_library(
        name = headers,
        hdrs = hdrs,
        deps = deps + [Label("//source:headers")],
        defines = defines,
        includes = includes,
        visibility = ["//visibility:private"],
        **common
    )
    cc_library(
        name = implementation,
        srcs = srcs,
        deps = [":" + headers],
        copts = copts,
        local_defines = local_defines + [_project_name(project) + "_EXPORT=1"],
        linkopts = linkopts,
        linkstatic = True,
        features = features,
        tags = tags,
        visibility = ["//visibility:private"],
        **common
    )
    cc_shared_library(
        name = shared,
        deps = [":" + implementation],
        shared_lib_name = shared_lib_name or select({WINDOWS: name + ".dll", "//conditions:default": "lib" + name + ".so"}),
        tags = tags + ["__DONT_DEPEND_ON_DEF_PARSER__"],
        features = features + ["-windows_export_all_symbols"],
        user_link_flags = select({LINUX: ["-Wl,-z,defs", "-Wl,-rpath,$ORIGIN"], "//conditions:default": []}) + user_link_flags,
        visibility = ["//visibility:private"],
        **kwargs
    )
    native.filegroup(
        name = interface,
        srcs = [":" + shared],
        output_group = "interface_library",
        visibility = ["//visibility:private"],
        **common
    )
    cc_import(
        name = name,
        shared_library = ":" + shared,
        interface_library = select({WINDOWS: ":" + interface, "//conditions:default": None}),
        deps = [":" + headers],
        linkopts = linkopts,
        visibility = visibility,
        **common
    )
