# Copyright (c) 2023-present Matt Kaes and contributors

"""Build a private current-worktree archive for external-consumer tests."""

load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

def candidate_snapshot():
    """Declare the test-only Toolchain archive consumed by sdk.py."""
    template = "validation/data/sdk/toolchain.BUILD.tpl"
    pkg_tar(
        name = "_candidate_snapshot",
        srcs = [
            ".bazelrc",
            ".bazelversion",
            "LICENSE",
            "MODULE.bazel",
            "defs.bzl",
            "//source:sources",
            "//validation/data:sdk/toolchain.BUILD.tpl",
        ],
        extension = "tar.gz",
        mode = "0644",
        package_file_name = native.module_name() + "-" + native.module_version() + "-source.tar.gz",
        remap_paths = {template: "BUILD"},
        strip_prefix = ".",
        tags = ["manual"],
        visibility = ["//validation/integration:__pkg__"],
    )
