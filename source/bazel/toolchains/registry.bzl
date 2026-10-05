# Copyright (c) 2023-present Matt Kaes and contributors

"""Compose target-owned toolchains and the source distribution.

Each target module owns its SDK repository, compiler configuration and root
labels. This registry names the supported set without sharing their machinery.
"""

load("@rules_pkg//pkg:tar.bzl", "pkg_tar")
load(":toolchains/linux/toolchain.bzl", "linux_targets")
load(":toolchains/wasm/toolchain.bzl", "wasm_targets")
load(":toolchains/windows/toolchain.bzl", "windows_targets")

# The root bootstrap declares one fixed set of labels used by MODULE.bazel.
# A caller supplied name would not control those platform and compiler labels.
# buildifier: disable=unnamed-macro
def toolchains():
    """Declare every supported target and the Toolchain source archive.

    Called once from the repository root BUILD file to define the public
    labels used by consuming modules for toolchain registration.
    """
    linux_targets()
    wasm_targets()
    windows_targets()

    pkg_tar(
        name = "sdk",
        srcs = [":sources"],
        package_file_name = native.module_name() + "-" + native.module_version() + "-source.tar.gz",
        extension = "tar.gz",
        mode = "0644",
        strip_prefix = ".",
        stamp = 0,
    )
