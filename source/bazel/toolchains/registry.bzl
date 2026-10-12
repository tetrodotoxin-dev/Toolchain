# Copyright (c) 2023-present Matt Kaes and contributors

"""Compose target-owned toolchains.

Each target module owns its SDK repository, compiler configuration and root
labels. This registry composes those public labels while each target retains its
own machinery.
"""

load(":toolchains/linux/toolchain.bzl", "linux_targets")
load(":toolchains/wasm/toolchain.bzl", "wasm_targets")
load(":toolchains/windows/toolchain.bzl", "windows_targets")

# The root bootstrap owns the fixed platform and compiler labels registered by
# MODULE.bazel, so the declaration has one canonical name set.
# buildifier: disable=unnamed-macro
def toolchains():
    """Declare every supported target toolchain.

    Called once from the repository root BUILD file to define the public
    labels used by consuming modules for toolchain registration.
    """
    linux_targets()
    wasm_targets()
    windows_targets()
