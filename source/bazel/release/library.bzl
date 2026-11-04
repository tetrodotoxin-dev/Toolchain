# Copyright (c) 2023-present Matt Kaes and contributors

"""Combine SDK link dependencies using their published payload identities."""

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_SdkLibrariesInfo = provider(
    "Published payload identities and the selected shared library inputs.",
    fields = {
        "digests": "Content digests indexed by the original SDK file.",
        "runtime": "Selected shared libraries indexed by their runtime filename.",
    },
)

def _field(records, name, default = None):
    """Select one attribute from the records for the supported platforms."""
    return select({platform: record.get(name, default) for platform, record in records.items()})

def _primary_library(platforms, linkage):
    """Select the primary file only for the linkage recorded by its archive."""
    return select({
        platform: metadata["library"] if metadata["linkage"] == linkage else None
        for platform, metadata in platforms.items()
    })

def _imports(platforms, kind):
    """Declare each platform-selected dependency and return its target labels.

    Runtime DLLs, static archives and host interfaces retain their distinct
    linker roles. Empty slots let one target inventory serve every platform.
    """
    prefix = "archive" if kind == "archives" else kind
    count = max([len(metadata[kind]) for metadata in platforms.values()])
    for index in range(count):
        records = {
            platform: metadata[kind][index] if index < len(metadata[kind]) else {}
            for platform, metadata in platforms.items()
        }

        cc_import(
            name = prefix + "_" + str(index),
            interface_library = _field(records, "interface"),
            static_library = _field(records, "library") if kind == "archives" else None,
            shared_library = _field(records, "library") if kind == "runtime" else None,
            linkopts = _field(records, "linkopts", []),
            alwayslink = _field(records, "alwayslink", False),
            system_provided = kind == "system",
            visibility = ["//visibility:private"],
        )

    return select({
        platform: [":" + prefix + "_" + str(index) for index in range(len(metadata[kind]))]
        for platform, metadata in platforms.items()
    })

def sdk_import(library, dependencies, implementation_dependencies, platforms, components):
    """Declare the release binary and the header interfaces that consumers use.

    Each platform record retains the archive's metadata and resolved file paths.
    Native C++ attributes select their own field from those same records.
    """
    imported = _imports(platforms, "runtime") + _imports(platforms, "archives") + _imports(platforms, "system")
    cc_library(
        name = "headers",
        hdrs = native.glob(["headers/include/**/*.h", "headers/include/**/*.hpp"], allow_empty = True),
        defines = _field(platforms, "defines"),
        implementation_deps = implementation_dependencies,
        strip_include_prefix = "headers/include",
        deps = dependencies,
    )

    cc_import(
        name = "_sdk_library",
        interface_library = _field(platforms, "interface"),
        linkopts = _field(platforms, "linkopts"),
        shared_library = _primary_library(platforms, "shared"),
        static_library = _primary_library(platforms, "static"),
        deps = [":headers"] + imported,
        alwayslink = _field(platforms, "alwayslink", False),
        visibility = ["//visibility:private"],
    )

    sdk_library(
        name = library,
        actual = ":_sdk_library",
        digests = _field(platforms, "sha256"),
        deps = dependencies + implementation_dependencies,
    )

    native.filegroup(name = "build", srcs = _field(platforms, "binaries"))

    # These header targets create the virtual include trees used by both the
    # compiler and editor navigation. Sharing the binary keeps their header
    # scopes independent while preserving each component's dependency edges.
    for name, component in components.items():
        cc_library(
            name = "_sdk_component_" + name,
            hdrs = select(component["headers"]),
            defines = select(component["defines"]),
            implementation_deps = [library],
            strip_include_prefix = "headers/include",
            deps = component["dependencies"],
            visibility = ["//visibility:private"],
        )

        sdk_library(
            name = name,
            actual = ":_sdk_component_" + name,
            deps = [library] + component["dependencies"],
        )

def _binary(library):
    """Return the original runtime file before Bazel's shared library symlink."""
    return library.resolved_symlink_dynamic_library or library.dynamic_library

def _signature(library, digests):
    """Identify a published runtime and its optional linker interface.

    Args:
        library: C++ shared library input being compared.
        digests: Published content digests indexed by SDK files.

    Returns:
        Content and link requirements, or None for an input outside these SDKs.
    """
    binary = _binary(library)
    interface = library.resolved_symlink_interface_library or library.interface_library
    if binary not in digests or (interface and interface not in digests):
        return None

    return (
        digests[binary],
        interface.basename if interface else None,
        digests.get(interface),
        library.alwayslink,
    )

def _select(runtime, library, digests):
    """Reuse an identical SDK runtime or reject conflicting published contents.

    Args:
        runtime: Selected libraries indexed by runtime filename, updated in place.
        library: Incoming library from the actual C++ dependency graph.
        digests: Published content digests indexed by SDK files.

    Returns:
        The selected library. Inputs without SDK identity keep their own record.
    """
    signature = _signature(library, digests)
    if signature == None:
        return library

    name = _binary(library).basename
    if name in runtime and _signature(runtime[name], digests) != signature:
        fail("Conflicting SDK runtime contents or link requirements for " + name)

    return runtime.setdefault(name, library)

def _library_impl(ctx):
    """Preserve a C++ interface while reconciling its SDK runtime dependencies.

    Args:
        ctx: Rule context carrying the interface, SDK identities and dependencies.

    Returns:
        The original compilation interface, reconciled linker inputs and SDK
        identities for further composition. Headers retain their declared scope.
    """
    digests = {}
    for dependency in ctx.attr.deps:
        if _SdkLibrariesInfo in dependency:
            digests.update(dependency[_SdkLibrariesInfo].digests)

    for target, digest in ctx.attr.digests.items():
        digests[target[DefaultInfo].files.to_list()[0]] = digest

    # A component keeps the runtime choices already made by its common library.
    # This also gives aggregate and component consumers the same DLL source
    # when Windows stages both executables in one output directory.
    preferred = {}
    for dependency in ctx.attr.deps:
        if _SdkLibrariesInfo in dependency:
            for library in dependency[_SdkLibrariesInfo].runtime.values():
                _select(preferred, library, digests)

    actual = ctx.attr.actual[CcInfo]
    inputs = []
    selected = {}
    seen = {}
    for entry in actual.linking_context.linker_inputs.to_list():
        libraries = []
        for library in entry.libraries:
            library = _select(preferred, library, digests)
            if _signature(library, digests) != None:
                selected[_binary(library).basename] = library
                if _binary(library) in seen:
                    continue

                seen[_binary(library)] = True

            libraries.append(library)

        # Packaging identifies the primary library by its public target.
        # Dependency inputs retain their original declaring targets.
        inputs.append(
            cc_common.create_linker_input(
                owner = (
                    ctx.label if entry.owner == ctx.attr.actual.label else entry.owner
                ),
                libraries = depset(libraries),
                user_link_flags = entry.user_link_flags,
                additional_inputs = depset(entry.additional_inputs),
                linkstamps = depset(entry.linkstamps),
            ),
        )

    return [
        ctx.attr.actual[DefaultInfo],
        CcInfo(
            compilation_context = actual.compilation_context,
            linking_context = cc_common.create_linking_context(
                linker_inputs = depset(inputs),
            ),
        ),
        _SdkLibrariesInfo(digests = digests, runtime = selected),
    ]

sdk_library = rule(
    implementation = _library_impl,
    provides = [CcInfo, _SdkLibrariesInfo],
    attrs = {
        "actual": attr.label(mandatory = True, providers = [CcInfo]),
        "deps": attr.label_list(),
        "digests": attr.label_keyed_string_dict(allow_files = True),
    },
)
