# Copyright (c) 2023-present Matt Kaes and contributors

"""Publish independent SDKs beside the repository's primary module."""

load("@tetro_toolchain//:defs.bzl", "package")

# Declare an auxiliary package first so the primary runtime cannot be chosen
# accidentally by declaration order. All three use existing imported targets.
package(
    name = "cpu_sdk",
    module = "auxiliary_cpu",
    static = "//source:api",
    platforms = ["{platform}"],
)

package(
    name = "primary_sdk",
    module = "consumer",
    static = "//source:toolchain_test",
    platforms = ["{platform}"],
)

package(
    name = "accelerator_sdk",
    module = "auxiliary_accelerator",
    static = "//source:public",
    platforms = ["{platform}"],
)
