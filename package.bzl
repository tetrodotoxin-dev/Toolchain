# # Tetrodotoxin
# Copyright (c) 2023-present Matt Kaes and contributors

"""Package declared outputs using the same layout across project releases.

A destination ending in / preserves paths relative to this BUILD package.
Other destinations name one exact file. This keeps the file map explicit and
lets Bazel schedule its producers without a packaging script running builds.
"""

load("@rules_pkg//pkg:mappings.bzl", "pkg_files", "strip_prefix")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

def _files(name, files, testonly):
    parts = []
    for index, (source, destination) in enumerate(files.items()):
        part = name + "_files_" + str(index)
        directory = destination.endswith("/")
        pkg_files(
            name = part,
            srcs = [source],
            prefix = destination.rstrip("/") if directory else "",
            renames = {} if directory else {source: destination},
            strip_prefix = strip_prefix.from_pkg() if directory and destination.startswith("include/") else strip_prefix.files_only(),
            testonly = testonly,
            visibility = ["//visibility:private"],
        )
        parts.append(":" + part)
    return parts

def sdk_release(name, files, platforms, version = None, package_name = None, platform_files = {}, **kwargs):
    parts = _files(name, files, kwargs.get("testonly", False))
    for index, (platform, additions) in enumerate(platform_files.items()):
        parts += select({platform: _files(name + "_platform_" + str(index), additions, kwargs.get("testonly", False)), "//conditions:default": []})
    pkg_tar(
        name = name,
        srcs = parts,
        package_file_name = select({
            condition: "{}-{}-{}.tar.gz".format(
                package_name or native.module_name(),
                version or native.module_version(),
                platform,
            )
            for condition, platform in platforms.items()
        }),
        extension = "tar.gz",
        mode = "0644",
        stamp = 0,
        **kwargs
    )
