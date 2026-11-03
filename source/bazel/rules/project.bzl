# Copyright (c) 2023-present Matt Kaes and contributors

"""Build a source project from the component targets in its root BUILD file.

Components own their files and dependency edges. The project combines their
objects into one SDK runtime and publishes the same component interfaces.
Native validation uses the shared runtime so missing exports fail before
release; Web validation links the static runtime into its Node program.
"""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_static_library.bzl", "cc_static_library")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":package.bzl", "package")
load(":rules/format.bzl", "format")
load(":rules/library.bzl", "WINDOWS", "shared_library", "static_library")
load(":rules/validation.bzl", "validation")
load(":rules/setup.bzl", "setup")

_HEADERS = ["h", "hpp"]
_SOURCES = ["c", "cpp"]


def _root():
    if native.package_name():
        fail("project declarations belong in the repository root BUILD file")


def _files(name, extensions):
    root = "source/" + native.module_name() + "/" + name + "/"
    return native.glob([root + "**/*." + extension for extension in extensions], allow_empty = True)


def _shared(label):
    target = native.package_relative_label(label)
    if target.workspace_root == native.package_relative_label(":_").workspace_root and not target.package:
        return ":_" + target.name + "_shared"
    return label


def component(
        name,
        deps = [],
        srcs = None,
        hdrs = None,
        defines = [],
        local_defines = [],
        implementation_deps = [],
        **kwargs):
    """Compile one component from source/<module>/<name> and its declared deps.

    The public target is a static C++ library. A private compilation uses the
    project's export annotation for its shared runtime. Local dependencies name
    other components; external SDK labels keep their own linkage and defines.
    Explicit file lists and ordinary C++ attributes cover generated inputs and
    component-specific system requirements without changing the source layout.
    """
    _root()
    sources = _files(name, _SOURCES) if srcs == None else srcs
    headers = _files(name, _HEADERS) if hdrs == None else hdrs
    common = dict(kwargs)
    common.setdefault("visibility", ["//visibility:public"])
    static_library(
        name = name,
        srcs = sources,
        hdrs = headers,
        includes = ["source"],
        deps = deps,
        implementation_deps = implementation_deps,
        defines = defines,
        local_defines = local_defines,
        **common
    )
    common["visibility"] = ["//visibility:private"]
    common["linkstatic"] = True
    common["alwayslink"] = True
    cc_library(
        name = "_" + name + "_shared",
        srcs = sources,
        hdrs = headers,
        includes = ["source"],
        deps = [_shared(dep) for dep in deps] + [Label("//source:headers")],
        implementation_deps = [_shared(dep) for dep in implementation_deps],
        defines = defines,
        local_defines = local_defines + [native.module_name().upper().replace("-", "_").replace(".", "_") + "_EXPORT=1"],
        **common
    )


def binary(name, deps = [], srcs = None, **kwargs):
    """Declare a native executable using source/<module>/<name> by default."""
    _root()
    cc_binary(
        name = name,
        srcs = _files(name, _SOURCES + _HEADERS) if srcs == None else srcs,
        deps = deps + [Label("//source:headers")],
        **kwargs
    )


def _component_interface_impl(ctx):
    """Keep headers and link requirements left outside the project runtime.

    The project library absorbs component objects. Prebuilt SDK libraries and
    authored linker flags remain requirements of its consumers, alongside the
    component headers and definitions.
    """
    merged = cc_common.merge_cc_infos(cc_infos = [dep[CcInfo] for dep in ctx.attr.deps])
    inputs = []
    for entry in merged.linking_context.linker_inputs.to_list():
        libraries = [library for library in entry.libraries if not library.objects and not library.pic_objects]
        inputs.append(cc_common.create_linker_input(
            owner = entry.owner,
            libraries = depset(libraries),
            user_link_flags = entry.user_link_flags,
            additional_inputs = depset(entry.additional_inputs),
        ))
    return [
        CcInfo(
            compilation_context = merged.compilation_context,
            linking_context = cc_common.create_linking_context(linker_inputs = depset(inputs)),
        ),
        DefaultInfo(runfiles = ctx.runfiles().merge_all([dep[DefaultInfo].default_runfiles for dep in ctx.attr.deps])),
    ]


_component_interface = rule(
    implementation = _component_interface_impl,
    attrs = {"deps": attr.label_list(providers = [CcInfo])},
)


def project(name = None, components = []):
    """Publish the component graph as static/shared SDKs and runnable validation.

    Name defaults to the MODULE.bazel identity and must match it. Components
    supply the source graph once; SDK metadata follows their actual dependency
    targets. The standard format, tests, benchmarks, Web runners, SDK release
    and setup commands are declared together from this root entry point.
    """
    _root()
    name = name or native.module_name()
    if name != native.module_name():
        fail("project name must match MODULE.bazel")
    cc_static_library(
        name = "_" + name + "_archive",
        deps = components,
        # LLVM's Windows librarian does not implement MSVC's symbol-check flag.
        features = select({WINDOWS: ["-symbol_check"], "//conditions:default": []}),
        visibility = ["//visibility:private"],
    )
    _component_interface(
        name = "_" + name + "_interface",
        deps = components,
        visibility = ["//visibility:private"],
    )
    cc_import(
        name = name,
        static_library = ":_" + name + "_archive",
        deps = [":_" + name + "_interface"],
        visibility = ["//visibility:public"],
    )
    _component_interface(
        name = "_" + name + "_shared_interface",
        deps = [_shared(component) for component in components],
        visibility = ["//visibility:private"],
    )
    shared_library(
        name = name + "_shared",
        deps = [_shared(component) for component in components],
        exports_filter = [_shared(component) for component in components],
        header_deps = [":_" + name + "_shared_interface"],
        shared_lib_name = select({WINDOWS: name + ".dll", "//conditions:default": "lib" + name + ".so"}),
        visibility = ["//visibility:public"],
    )
    package(module = name, components = components, static = ":" + name, shared = ":" + name + "_shared")
    format()
    validation(deps = [":" + name + "_shared"], web_deps = [":" + name])
    setup()
