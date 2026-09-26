# Copyright (c) 2023-present Matt Kaes and contributors

"""Import versioned binary archives with consumer-selected dependency pins.

A module declares releases and hashes here, rather than copying repository
rules or embedding build files in the SDK. Native build tools and Wasm output
can coexist in the same graph, so every declared platform stays available.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _sdk(ctx):
    for platform, checksum in ctx.attr.archives.items():
        ctx.download_and_extract(
            url = "https://github.com/tetrodotoxin-dev/" + ctx.attr.project + "/releases/download/v" + ctx.attr.version + "/" + ctx.attr.library + "-" + ctx.attr.version + "-" + platform + ".tar.gz",
            sha256 = checksum,
            output = platform,
        )
    first = ctx.attr.archives.keys()[0]
    libraries = {}
    interfaces = {}
    for platform in ctx.attr.archives:
        condition = {"linux-x86_64-v3": "@tetro_toolchain//:linux", "wasm32-emscripten": "@tetro_toolchain//:web", "windows-x86_64-msvc": "@tetro_toolchain//:windows"}[platform]
        libraries[condition] = platform + "/lib/" + (ctx.attr.library + ".dll" if platform == "windows-x86_64-msvc" else "lib" + ctx.attr.library + ".so")
        interfaces[condition] = platform + "/lib/" + ctx.attr.library + ".lib" if platform == "windows-x86_64-msvc" else None
    ctx.file("BUILD.bazel", """load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_import.bzl", "cc_import")
package(default_visibility = ["//visibility:public"])
cc_library(name = "headers", hdrs = glob(["%s/include/**/*.h", "%s/include/**/*.hpp"], allow_empty = True), strip_include_prefix = "%s/include", deps = %s, defines = %s)
cc_import(name = "%s", shared_library = select(%s), interface_library = select(%s), deps = [":headers"])
filegroup(name = "build", srcs = select({key: [value] for key, value in %s.items()}))
""" % (first, first, first, repr(ctx.attr.deps), ctx.attr.defines, ctx.attr.library, repr(libraries), repr(interfaces), repr(libraries)))

_sdk_repository = repository_rule(implementation = _sdk, attrs = {
    "library": attr.string(mandatory = True),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "archives": attr.string_dict(mandatory = True),
    "deps": attr.string_list(),
    "defines": attr.string(default = "[]"),
})

def _dependencies(ctx):
    seen = {}
    for module in ctx.modules:
        for release in module.tags.release:
            if release.name in seen:
                if seen[release.name] != (release.project, release.version, release.archives, release.deps):
                    fail("Conflicting SDK release pins for " + release.name)
                continue
            seen[release.name] = (release.project, release.version, release.archives, release.deps)
            defines = 'select({"@tetro_toolchain//:linux": ["PERI_LINUX"], "@tetro_toolchain//:web": ["PERI_WASM"], "@tetro_toolchain//:windows": ["PERI_WINDOWS"]})' if release.name == "perimortem" else "[]"
            _sdk_repository(name = release.name, library = release.name, project = release.project, version = release.version, archives = release.archives, deps = release.deps, defines = defines)
        for support in module.tags.test_support:
            http_archive(name = support.name, urls = [support.url], sha256 = support.sha256, build_file = Label("//:test_support.BUILD.bazel"))

_release = tag_class(attrs = {"name": attr.string(mandatory = True), "project": attr.string(mandatory = True), "version": attr.string(mandatory = True), "archives": attr.string_dict(mandatory = True), "deps": attr.string_list()})
_test_support = tag_class(attrs = {"name": attr.string(default = "perimortem_test"), "url": attr.string(mandatory = True), "sha256": attr.string(mandatory = True)})
dependencies = module_extension(implementation = _dependencies, tag_classes = {"release": _release, "test_support": _test_support})
