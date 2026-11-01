# Copyright (c) 2023-present Matt Kaes and contributors

"""Import one packaged library and its component interfaces."""

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@tetro_toolchain//source/bazel:release/library.bzl", "sdk_library")

package(default_visibility = ["//visibility:public"])

# Each platform may have a different dependency set. Only the imports selected
# by that platform enter the consuming target's link and runtime dependencies.
_RUNTIME = {runtime}

_ARCHIVES = {archives}

_SYSTEM = {system}

[
    cc_import(
        name = "system_" + str(index),
        interface_library = select({
            platform: libraries[index]["interface"] if index < len(libraries) else None
            for platform, libraries in _SYSTEM.items()
        }),
        linkopts = select({
            platform: libraries[index]["linkopts"] if index < len(libraries) else []
            for platform, libraries in _SYSTEM.items()
        }),
        system_provided = True,
        visibility = ["//visibility:private"],
    )
    for index in range(max([len(libraries) for libraries in _SYSTEM.values()]))
]

[
    cc_import(
        name = "archive_" + str(index),
        linkopts = select({
            platform: libraries[index]["linkopts"] if index < len(libraries) else []
            for platform, libraries in _ARCHIVES.items()
        }),
        static_library = select({
            platform: libraries[index]["library"] if index < len(libraries) else None
            for platform, libraries in _ARCHIVES.items()
        }),
        visibility = ["//visibility:private"],
        alwayslink = select({
            platform: libraries[index]["alwayslink"] if index < len(libraries) else False
            for platform, libraries in _ARCHIVES.items()
        }),
    )
    for index in range(max([len(libraries) for libraries in _ARCHIVES.values()]))
]

[
    cc_import(
        name = "runtime_" + str(index),
        interface_library = select({
            platform: libraries[index]["interface"] if index < len(libraries) else None
            for platform, libraries in _RUNTIME.items()
        }),
        shared_library = select({
            platform: libraries[index]["library"] if index < len(libraries) else None
            for platform, libraries in _RUNTIME.items()
        }),
        visibility = ["//visibility:private"],
    )
    for index in range(max([len(libraries) for libraries in _RUNTIME.values()]))
]

cc_library(
    name = "headers",
    hdrs = glob(
        [
            "headers/include/**/*.h",
            "headers/include/**/*.hpp",
        ],
        allow_empty = True,
    ),
    defines = select({defines}),
    implementation_deps = {implementation_dependencies},
    strip_include_prefix = "headers/include",
    deps = {dependencies},
)

cc_import(
    name = "_sdk_library",
    interface_library = select({interface_libraries}),
    linkopts = select({linkopts}),
    shared_library = select({shared_libraries}),
    static_library = select({static_libraries}),
    deps = [":headers"] + select({
        platform: [":runtime_" + str(index) for index in range(len(libraries))]
        for platform, libraries in _RUNTIME.items()
    }) + select({
        platform: [":archive_" + str(index) for index in range(len(libraries))]
        for platform, libraries in _ARCHIVES.items()
    }) + select({
        platform: [":system_" + str(index) for index in range(len(libraries))]
        for platform, libraries in _SYSTEM.items()
    }),
    alwayslink = select({alwayslink}),
    visibility = ["//visibility:private"],
)

sdk_library(
    name = {library},
    actual = ":_sdk_library",
    digests = select({digests}),
    deps = {dependencies} + {implementation_dependencies},
)

filegroup(
    name = "build",
    srcs = select({binaries}),
)

# Components share the selected binary while keeping the aggregate header
# interface private. Scoped archives retain sibling edges and receive external
# labels from the consuming module's component declarations.
_COMPONENTS = {components}

[
    cc_library(
        name = "_sdk_component_" + name,
        hdrs = select(component["headers"]),
        defines = select(component["defines"]),
        implementation_deps = [{library}],
        strip_include_prefix = "headers/include",
        deps = component["dependencies"],
        visibility = ["//visibility:private"],
    )
    for name, component in _COMPONENTS.items()
]

[
    sdk_library(
        name = name,
        actual = ":_sdk_component_" + name,
        deps = [{library}] + component["dependencies"],
    )
    for name, component in _COMPONENTS.items()
]
