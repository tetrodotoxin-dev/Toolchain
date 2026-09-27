# Copyright (c) 2023-present Matt Kaes and contributors

"""Import a release's shared headers and target binaries without rebuilding it."""

_PLATFORMS = {
    "linux-x86_64-v3": "@tetro_toolchain//:linux",
    "windows-x86_64-msvc": "@tetro_toolchain//:windows",
    "wasm32-emscripten": "@tetro_toolchain//:web",
}

def _sdk(ctx):
    if "headers" not in ctx.attr.archives:
        fail("An SDK pin must include its shared headers archive")
    for archive, checksum in ctx.attr.archives.items():
        ctx.download_and_extract(
            url = "https://github.com/tetrodotoxin-dev/" + ctx.attr.project + "/releases/download/v" + ctx.attr.version + "/" + ctx.attr.library + "-" + ctx.attr.version + "-" + archive + ".zip",
            sha256 = checksum,
            output = archive,
        )
    libraries = {}
    interfaces = {}
    for platform, condition in _PLATFORMS.items():
        if platform not in ctx.attr.archives:
            continue
        windows = platform == "windows-x86_64-msvc"
        libraries[condition] = platform + "/lib/" + (ctx.attr.library + ".dll" if windows else "lib" + ctx.attr.library + ".so")
        interfaces[condition] = platform + "/lib/" + ctx.attr.library + ".lib" if windows else None
    ctx.file("BUILD.bazel", """load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_import.bzl", "cc_import")
package(default_visibility = ["//visibility:public"])
cc_library(name = "headers", hdrs = glob(["headers/include/**/*.h", "headers/include/**/*.hpp"]), strip_include_prefix = "headers/include", deps = %s)
cc_import(name = "%s", shared_library = select(%s), interface_library = select(%s), deps = [":headers"])
filegroup(name = "build", srcs = select({key: [value] for key, value in %s.items()}))
""" % (repr(ctx.attr.deps), ctx.attr.library, repr(libraries), repr(interfaces), repr(libraries)))

_sdk_repository = repository_rule(implementation = _sdk, attrs = {
    "library": attr.string(mandatory = True),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "archives": attr.string_dict(mandatory = True),
    "deps": attr.string_list(),
})

def _dependencies(ctx):
    seen = {}
    for module in ctx.modules:
        for release in module.tags.release:
            pin = (release.project, release.version, release.archives, release.deps)
            if release.name in seen:
                if seen[release.name] != pin:
                    fail("Conflicting SDK release pins for " + release.name)
                continue
            seen[release.name] = pin
            _sdk_repository(name = release.name, library = release.name, project = release.project, version = release.version, archives = release.archives, deps = release.deps)

_release = tag_class(attrs = {"name": attr.string(mandatory = True), "project": attr.string(mandatory = True), "version": attr.string(mandatory = True), "archives": attr.string_dict(mandatory = True), "deps": attr.string_list()})
dependencies = module_extension(implementation = _dependencies, tag_classes = {"release": _release})
