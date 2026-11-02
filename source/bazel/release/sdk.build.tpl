# Copyright (c) 2023-present Matt Kaes and contributors

load("@tetro_toolchain//source/bazel:release/library.bzl", "sdk_import")

package(default_visibility = ["//visibility:public"])

sdk_import(
    library = {library},
    dependencies = {dependencies},
    implementation_dependencies = {implementation_dependencies},
    static_libraries = {static_libraries},
    shared_libraries = {shared_libraries},
    interface_libraries = {interface_libraries},
    defines = {defines},
    linkopts = {linkopts},
    alwayslink = {alwayslink},
    runtime = {runtime},
    archives = {archives},
    digests = {digests},
    system = {system},
    binaries = {binaries},
    components = {components},
)
