# Copyright (c) 2023-present Matt Kaes and contributors

load("@tetro_toolchain//source/bazel:release/library.bzl", "sdk_import")

package(default_visibility = ["//visibility:public"])

sdk_import(
    library = {library},
    dependencies = {dependencies},
    implementation_dependencies = {implementation_dependencies},
    platforms = {platforms},
    components = {components},
)
