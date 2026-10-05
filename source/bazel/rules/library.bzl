# Copyright (c) 2023-present Matt Kaes and contributors

"""Compile static libraries and explicitly exported shared libraries."""

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_cc//cc/common:cc_shared_library_info.bzl", "CcSharedLibraryInfo")
load(":toolchains/platforms.bzl", "PLATFORMS")

LINUX = PLATFORMS["linux-x86_64-v3"].condition
WEB = PLATFORMS["wasm32-emscripten"].condition
WINDOWS = PLATFORMS["windows-x86_64-msvc"].condition

def library(name = None, module = None, linkage = "static", components = {}, srcs = [], hdrs = [], includes = [], deps = [], defines = [], **kwargs):
    """Compile a library and declare its component header interfaces.

    Components follow the source/<module>/<component> layout. Their dependency
    mapping describes public header requirements. The common runtime contains
    the implementations, including dependencies private to those implementations.
    Declare these neutral header interfaces once when compiling both variants.

    Args:
        name: Compiled target name, defaulting to module.
        module: Library identity and header directory, defaulting to the Bazel
            module name. Its uppercase spelling identifies EXPORTED(MODULE).
        linkage: Either static or shared, defaulting to static.
        components: Component names mapped to their component dependencies.
        srcs: Implementation sources.
        hdrs: Public headers for the complete library.
        includes: Public include directories relative to this Bazel package.
        deps: External dependencies required by the public headers.
        defines: Definitions shared by the library and component consumers.
        **kwargs: Additional attributes for the selected library variant.
    """
    module = module or native.module_name()
    if linkage not in ["static", "shared"]:
        fail("library linkage must be static or shared")
    common = {key: kwargs[key] for key in ["visibility", "testonly", "target_compatible_with", "compatible_with"] if key in kwargs}
    for component, dependencies in components.items():
        cc_library(
            name = component,
            hdrs = native.glob([module + "/" + component + "/**/*.h", module + "/" + component + "/**/*.hpp"], allow_empty = True),
            includes = includes,
            defines = defines,
            deps = [":" + dependency for dependency in dependencies] + deps + [Label("//source:headers")],
            **common
        )
    compile_library = static_library if linkage == "static" else shared_library
    compile_library(
        name = name or module,
        project = module,
        srcs = srcs,
        hdrs = hdrs,
        includes = includes,
        deps = deps,
        defines = defines,
        **kwargs
    )

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

def static_library(name, deps = [], project = None, defines = [], implementation_deps = [], **kwargs):
    """Compile a static library with Toolchain's export annotation available.

    PROJECT_STATIC=1 reaches this implementation and its consumers so both
    use ordinary declarations for EXPORTED(PROJECT).

    Args:
        name: Static library target name.
        deps: C++ dependencies required by the public interface.
        implementation_deps: Dependencies whose headers and definitions are
            available only to this library's sources. Link requirements reach
            consumers because a static archive leaves its references unresolved.
        project: EXPORTED identifier, defaulting to the uppercase module name.
        defines: Additional definitions shared with consumers.
        **kwargs: Additional cc_library attributes.
    """
    cc_library(
        name = name,
        deps = deps + [Label("//source:headers")],
        implementation_deps = implementation_deps,
        defines = defines + [_project_name(project) + "_STATIC=1"],
        linkstatic = True,
        **kwargs
    )

def _shared_runtime_impl(ctx):
    """Expose the shared link's remaining dependencies without their headers.

    Args:
        ctx: Rule context selecting the completed cc_shared_library.

    Returns:
        C++ linker inputs for the remaining shared dependencies.
    """
    shared = ctx.attr.shared[CcSharedLibraryInfo]
    primary = ctx.attr.shared[DefaultInfo].files.to_list()

    # The completed link already distinguishes embedded static code from the
    # shared dependencies its consumers still need. Reuse that decision so an
    # alwayslink implementation archive cannot be linked into consumers again.
    libraries = [library for library in shared.linker_input.libraries if (library.resolved_symlink_dynamic_library or library.dynamic_library) not in primary]
    inputs = [cc_common.create_linker_input(owner = ctx.label, libraries = depset(libraries))]
    inputs.extend([dependency.linker_input for dependency in shared.dynamic_deps.to_list()])
    return [CcInfo(linking_context = cc_common.create_linking_context(linker_inputs = depset(inputs)))]

_shared_runtime = rule(
    implementation = _shared_runtime_impl,
    attrs = {"shared": attr.label(mandatory = True, providers = [CcSharedLibraryInfo])},
)

def shared_library(name, srcs = [], hdrs = [], deps = [], project = None, copts = [], defines = [], local_defines = [], includes = [], linkopts = [], shared_lib_name = None, user_link_flags = [], features = [], tags = [], implementation_deps = [], **kwargs):
    """Compile a shared library and expose its headers and binary to consumers.

    PROJECT_EXPORT=1 belongs to this target's source compilation. Consumers
    import EXPORTED(PROJECT) declarations with no additional definitions.
    Dependencies keep their own linkage and compilation settings.

    Args:
        name: Shared library target name and default binary stem.
        srcs: Implementation sources compiled with PROJECT_EXPORT=1.
        hdrs: Public headers available to this library and its consumers.
        deps: Libraries and headers required by the public interface.
        implementation_deps: Dependencies available to implementation sources.
            Their headers and definitions stay private. Static code is absorbed
            by this shared library and shared dependencies remain available to
            consumers and release packaging.
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
    runtime = name + "_runtime"
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
        implementation_deps = implementation_deps,
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
    _shared_runtime(
        name = runtime,
        shared = ":" + shared,
        visibility = ["//visibility:private"],
        **common
    )
    cc_import(
        name = name,
        shared_library = ":" + shared,
        interface_library = select({WINDOWS: ":" + interface, "//conditions:default": None}),
        deps = [":" + headers, ":" + runtime],
        linkopts = linkopts,
        visibility = visibility,
        **common
    )
