# Copyright (c) 2023-present Matt Kaes and contributors

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

# Each platform may have a different dependency set. Only the imports selected
# by that platform enter the consuming target's link and runtime dependencies.
_RUNTIME = {runtime}

[
    cc_import(
        name = "runtime_" + str(index),
        shared_library = select({
            platform: libraries[index]["library"] if index < len(libraries) else None
            for platform, libraries in _RUNTIME.items()
        }),
        interface_library = select({
            platform: libraries[index]["interface"] if index < len(libraries) else None
            for platform, libraries in _RUNTIME.items()
        }),
        visibility = ["//visibility:private"],
    )
    for index in range(max([len(libraries) for libraries in _RUNTIME.values()]))
]

cc_library(
    name = "headers",
    hdrs = glob(
        ["headers/include/**/*.h", "headers/include/**/*.hpp"],
        allow_empty = True,
    ),
    strip_include_prefix = "headers/include",
    defines = select({defines}),
    deps = {dependencies},
    implementation_deps = {implementation_dependencies},
)

cc_import(
    name = {library},
    static_library = select({static_libraries}),
    shared_library = select({shared_libraries}),
    interface_library = select({interface_libraries}),
    linkopts = select({linkopts}),
    deps = [":headers"] + select({
        platform: [":runtime_" + str(index) for index in range(len(libraries))]
        for platform, libraries in _RUNTIME.items()
    }),
)

filegroup(
    name = "build",
    srcs = select({binaries}),
)
