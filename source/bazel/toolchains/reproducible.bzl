# Copyright (c) 2023-present Matt Kaes and contributors

"""Keep compiler records independent of the execution host and build time."""

load("@host_tools//:settings.bzl", "RESOURCE_INCLUDE")

COMPILE_FLAGS = [
    "-ffile-compilation-dir=.",
    "-ffile-prefix-map=" + RESOURCE_INCLUDE + "=toolchain/clang/include",
    "-ffile-reproducible",
    "-Wno-builtin-macro-redefined",
    '-D__DATE__="redacted"',
    '-D__TIME__="redacted"',
    '-D__TIMESTAMP__="redacted"',
]
