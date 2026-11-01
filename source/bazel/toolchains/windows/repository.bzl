# Copyright (c) 2023-present Matt Kaes and contributors

"""Supply the MSVC headers and libraries used with the selected LLVM tools.

Pinned Microsoft archives are extracted only when a Windows target is requested.
TETRO_WINDOWS_SDK selects an existing SDK in winsysroot layout when a developer
wants to use an installed version instead.
"""

load("//source:sdk/normalize.bzl", "normalize_sdk")

def _sdk(ctx):
    """Assemble MSVC and Windows SDK files from downloads or an installed SDK.

    Args:
        ctx: Repository context with package pins, normalization tools and
            the optional installed-SDK selection.
    """
    source = ctx.os.environ.get("TETRO_WINDOWS_SDK")
    if source:
        # An explicit installed SDK remains useful when testing a newer vendor
        # release. The default path below always uses the pinned packages.
        root = ctx.path(source)
        crt = sorted(root.get_child("VC/Tools/MSVC").readdir())[-1]
        sdk = root.get_child("Windows Kits/10")
        version = sorted(sdk.get_child("Include").readdir())[-1].basename
        ctx.symlink(crt.get_child("include"), "include/crt")
        for name, path in {path.basename.lower(): path for path in crt.get_child("lib/x64").readdir()}.items():
            ctx.symlink(path, "lib/crt/" + name)
        for part in ["ucrt", "shared", "um", "winrt"]:
            ctx.symlink(sdk.get_child("Include/" + version + "/" + part), "include/" + part)
        for part in ["ucrt", "um"]:
            for name, path in {path.basename.lower(): path for path in sdk.get_child("Lib/" + version + "/" + part + "/x64").readdir()}.items():
                ctx.symlink(path, "lib/" + part + "/" + name)
    else:
        for index, package in enumerate(json.decode(ctx.read(ctx.attr._packages))):
            archive = "archives/" + str(index) + ".zip"
            ctx.download(url = package["url"], sha256 = package["sha256"], output = archive)
            for prefix, output in package["trees"].items():
                ctx.extract(archive, output = output, strip_prefix = prefix)
            ctx.delete(archive)
    normalize_sdk(ctx, "windows", ["external/" + ctx.name])

    # Runtime DLLs support local validation as development inputs. Product SDK
    # archives select runtime libraries from their declared dependency graph.
    ctx.template("BUILD.bazel", ctx.attr._build)
    return ctx.repo_metadata(reproducible = not source)

windows_sdk = repository_rule(implementation = _sdk, attrs = {
    "_build": attr.label(default = Label("//source/bazel:toolchains/windows/sdk.build.tpl")),
    "_packages": attr.label(default = Label("//source:sdk/windows.json")),
}, environ = ["TETRO_WINDOWS_SDK"])

