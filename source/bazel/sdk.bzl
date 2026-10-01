# Copyright (c) 2023-present Matt Kaes and contributors

"""Import a release's headers and one selected library linkage.

Each release tag supplies checksums for headers and platform archives, using
keys such as linux-x86_64-v3-shared and linux-x86_64-v3-static. Linkage defaults
to shared. Selecting static also publishes the project's STATIC definition.
Declare the selected variants of public dependencies in deps.
"""

load("@host_tools//:settings.bzl", "AR")

_PLATFORMS = {
    "linux-x86_64-v3": str(Label("//:linux")),
    "windows-x86_64-msvc": str(Label("//:windows")),
    "wasm32-emscripten": str(Label("//:web")),
}

def _sdk(ctx):
    """Import a pinned release's headers and libraries as C++ targets.

    Args:
        ctx: Repository context with release identity, archive checksums and
            dependency labels for the generated headers target.
    """
    if "headers" not in ctx.attr.archives:
        fail("An SDK pin must include its shared headers archive")
    selected = {"headers": "headers"}
    for platform in _PLATFORMS:
        archive = platform + "-" + ctx.attr.linkage
        if archive in ctx.attr.archives:
            selected[platform] = archive
        elif platform in ctx.attr.archives:
            # Earlier releases carried one linkage in each platform archive.
            selected[platform] = platform
    if len(selected) == 1:
        fail("No platform archives supply the requested " + ctx.attr.linkage + " linkage")
    for output, archive in selected.items():
        ctx.download_and_extract(
            url = "https://github.com/tetrodotoxin-dev/" + ctx.attr.project + "/releases/download/v" + ctx.attr.version + "/" + ctx.attr.library + "-" + ctx.attr.version + "-" + archive + ".zip",
            sha256 = ctx.attr.archives[archive],
            output = output,
        )
    if not ctx.path("headers/include/toolchain/export.h").exists:
        ctx.symlink(ctx.attr._export, "headers/include/toolchain/export.h")
    static_libraries = {}
    libraries = {}
    interfaces = {}
    defines = {}
    linkopts = {}
    for platform, condition in _PLATFORMS.items():
        if platform not in selected:
            continue
        windows = platform == "windows-x86_64-msvc"
        directory = platform + "/lib/"
        manifest = ctx.path(platform + "/sdk.json")
        metadata = {}
        if manifest.exists:
            metadata = json.decode(ctx.read(manifest))
            if metadata["linkage"] != ctx.attr.linkage:
                fail("SDK linkage disagrees with its pin for " + platform)
            binary = platform + "/" + metadata["library"]
            interface = platform + "/" + metadata["interface"] if metadata.get("interface") else None
            project = metadata["project"]
        else:
            shared = directory + (ctx.attr.library + ".dll" if windows else "lib" + ctx.attr.library + ".so")
            archive = directory + (ctx.attr.library + ".lib" if windows else "lib" + ctx.attr.library + ".a")
            static = ctx.path(archive).exists and not (windows and ctx.path(shared).exists)
            if static != (ctx.attr.linkage == "static"):
                fail("Legacy SDK archive does not supply " + ctx.attr.linkage + " linkage for " + platform)
            binary = archive if static else shared
            interface = directory + ctx.attr.library + ".lib" if windows and not static else None
            project = ctx.attr.library.upper().replace("-", "_").replace(".", "_")
        if not ctx.path(binary).exists or (interface and not ctx.path(interface).exists):
            fail("SDK archive is missing its declared linker output for " + platform)
        static = ctx.attr.linkage == "static"
        static_libraries[condition] = binary if static else None
        libraries[condition] = None if static else binary
        interfaces[condition] = interface
        defines[condition] = metadata.get("defines", [project + "_STATIC=1"] if static else [])
        linkopts[condition] = metadata.get("linkopts", [])
    ctx.template("BUILD.bazel", ctx.attr._template, substitutions = {
        "{dependencies}": repr(ctx.attr.deps),
        "{library}": repr(ctx.attr.library),
        "{static_libraries}": repr(static_libraries),
        "{shared_libraries}": repr(libraries),
        "{interface_libraries}": repr(interfaces),
        "{defines}": repr(defines),
        "{linkopts}": repr(linkopts),
        "{binaries}": repr({key: [static_libraries[key] or libraries[key]] for key in libraries}),
    }, executable = False)

_sdk_repository = repository_rule(implementation = _sdk, attrs = {
    "library": attr.string(mandatory = True),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "archives": attr.string_dict(mandatory = True),
    "deps": attr.string_list(),
    "linkage": attr.string(default = "shared", values = ["static", "shared"]),
    "_template": attr.label(default = Label("//source/bazel:sdk.BUILD.tpl")),
    "_export": attr.label(default = Label("//source:toolchain/export.h")),
})

def _dependencies(ctx):
    """Merge matching SDK pins and create one repository per release name.

    Args:
        ctx: Module extension context containing the modules' release tags.
    """
    seen = {}
    for module in ctx.modules:
        for release in module.tags.release:
            pin = (release.project, release.version, release.archives, release.deps, release.linkage)
            if release.name in seen:
                if seen[release.name] != pin:
                    fail("Conflicting SDK release pins for " + release.name)
                continue
            seen[release.name] = pin
            _sdk_repository(name = release.name, library = release.name, project = release.project, version = release.version, archives = release.archives, deps = [str(dep) for dep in release.deps], linkage = release.linkage)

_release = tag_class(attrs = {
    "name": attr.string(mandatory = True),
    "project": attr.string(mandatory = True),
    "version": attr.string(mandatory = True),
    "archives": attr.string_dict(mandatory = True),
    "deps": attr.label_list(),
    "linkage": attr.string(default = "shared", values = ["static", "shared"]),
})
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
