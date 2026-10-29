# Copyright (c) 2023-present Matt Kaes and contributors

load("//source/bazel:package.bzl", "package_release")

package(default_visibility = ["//validation/integration:__pkg__"])

# The same published contract can use either dependency linkage independently
# of its own output. A separate package keeps these alternative artifacts at
# distinct build paths while retaining the producer's real release identity.
package_release(
    name = "fixture",
    testonly = True,
    component_dependencies = {
        "api": ["public"],
        "public": [],
    },
    components = {
        "//validation/data:api": "api",
        "//validation/data:public": "public",
    },
    project = "toolchain_test",
    shared = "//validation/data:shared_static",
    static = "//validation/data:static_shared",
    tags = ["manual"],
)

filegroup(
    name = "checksum",
    tags = ["manual"],
    testonly = True,
    srcs = [":fixture"],
    output_group = "checksum",
)
