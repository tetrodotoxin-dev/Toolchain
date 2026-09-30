# Copyright (c) 2023-present Matt Kaes and contributors

"""Import a release's headers and static or shared libraries."""

load("@host_tools//:settings.bzl", "AR")

_PLATFORMS = {
    "linux-x86_64-v3": "@tetro_toolchain//:linux",
    "windows-x86_64-msvc": "@tetro_toolchain//:windows",
    "wasm32-emscripten": "@tetro_toolchain//:web",
}

def _sdk(ctx):
    """Import a pinned release's headers and libraries as C++ targets.

    Args:
        ctx: Repository context with release identity, archive checksums and
            dependency labels for the generated headers target.
    """
    if "headers" not in ctx.attr.archives:
        fail("An SDK pin must include its shared headers archive")
    for archive, checksum in ctx.attr.archives.items():
        ctx.download_and_extract(
            url = "https://github.com/tetrodotoxin-dev/" + ctx.attr.project + "/releases/download/v" + ctx.attr.version + "/" + ctx.attr.library + "-" + ctx.attr.version + "-" + archive + ".zip",
            sha256 = checksum,
            output = archive,
        )
    static_libraries = {}
    libraries = {}
    interfaces = {}
    for platform, condition in _PLATFORMS.items():
        if platform not in ctx.attr.archives:
            continue
        windows = platform == "windows-x86_64-msvc"
        directory = platform + "/lib/"
        shared = directory + (ctx.attr.library + ".dll" if windows else "lib" + ctx.attr.library + ".so")
        archive = directory + (ctx.attr.library + ".lib" if windows else "lib" + ctx.attr.library + ".a")

        # A Windows import library accompanies its DLL. Without that DLL the
        # .lib contains the implementation, just as an .a does on Linux.
        static = ctx.path(archive).exists and not (windows and ctx.path(shared).exists)
        if not static and not ctx.path(shared).exists:
            fail("SDK archive contains no library for " + platform)
        static_libraries[condition] = archive if static else None
        libraries[condition] = None if static else shared
        interfaces[condition] = directory + ctx.attr.library + ".lib" if windows and not static else None
    ctx.file("BUILD.bazel", """load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_import.bzl", "cc_import")
package(default_visibility = ["//visibility:public"])
cc_library(name = "headers", hdrs = glob(["headers/include/**/*.h", "headers/include/**/*.hpp"], allow_empty = True), strip_include_prefix = "headers/include", deps = %s)
cc_import(name = "%s", static_library = select(%s), shared_library = select(%s), interface_library = select(%s), deps = [":headers"])
filegroup(name = "build", srcs = select({key: [value] for key, value in %s.items()}))
""" % (repr(ctx.attr.deps), ctx.attr.library, repr(static_libraries), repr(libraries), repr(interfaces), repr({key: static_libraries[key] or libraries[key] for key in libraries})))

_sdk_repository = repository_rule(implementation = _sdk, attrs = {
    "library": attr.string(mandatory = True),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "archives": attr.string_dict(mandatory = True),
    "deps": attr.string_list(),
})

def _dependencies(ctx):
    """Merge matching SDK pins and create one repository per release name.

    Args:
        ctx: Module extension context containing the modules' release tags.
    """
    seen = {}
    for module in ctx.modules:
        for release in module.tags.release:
            pin = (release.project, release.version, release.archives, release.deps)
            if release.name in seen:
                if seen[release.name] != pin:
                    fail("Conflicting SDK release pins for " + release.name)
                continue
            seen[release.name] = pin
            _sdk_repository(name = release.name, library = release.name, project = release.project, version = release.version, archives = release.archives, deps = [str(dep) for dep in release.deps])

_release = tag_class(attrs = {"name": attr.string(mandatory = True), "project": attr.string(mandatory = True), "version": attr.string(mandatory = True), "archives": attr.string_dict(mandatory = True), "deps": attr.label_list()})
dependencies = module_extension(implementation = _dependencies, tag_classes = {"release": _release})

def extract_debian(ctx, archives):
    """Extract pinned Debian payloads into the repository without installing them.

    Args:
        ctx: Repository context receiving the extracted package files.
        archives: Dictionary mapping package download URLs to SHA256 checksums.
    """
    for index, (url, checksum) in enumerate(archives.items()):
        directory = "archives/" + str(index)
        archive = directory + "/package.deb"
        ctx.download(url = url, sha256 = checksum, output = archive)
        unpack = ctx.execute([AR, "x", str(ctx.path(archive))], working_directory = str(ctx.path(directory)))
        if unpack.return_code:
            fail(unpack.stderr)
        payload = [path for path in ctx.path(directory).readdir() if path.basename.startswith("data.tar.")]
        if len(payload) != 1:
            fail("SDK package has no unique data archive: " + url)
        ctx.extract(payload[0])
        ctx.delete(directory)

def _debian_sdk(ctx):
    """Extract Debian packages and expose them through the supplied BUILD file.

    Args:
        ctx: Repository context with archive pins and the BUILD file label.
    """
    extract_debian(ctx, ctx.attr.archives)
    ctx.file("BUILD.bazel", ctx.read(ctx.attr.build_file))

debian_sdk = repository_rule(implementation = _debian_sdk, attrs = {
    "archives": attr.string_dict(mandatory = True),
    "build_file": attr.label(mandatory = True, allow_single_file = True),
})
