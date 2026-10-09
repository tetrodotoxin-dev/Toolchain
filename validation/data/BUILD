load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//:defs.bzl", "library")

package(default_visibility = ["//validation:__pkg__"])

exports_files([
    "harness/reporting.cpp",
    "sdk/style.cpp",
] + glob(["sdk/*.tpl"]))

filegroup(
    name = "sources",
    srcs = glob(["**"]),
)

cc_binary(
    name = "reporting",
    testonly = True,
    srcs = ["harness/reporting.cpp"],
    tags = ["manual"],
    deps = ["//source/toolchain/validation:test"],
)

cc_binary(
    name = "skipped",
    testonly = True,
    srcs = ["harness/skipped.cpp"],
    deps = ["//source/toolchain/validation:test"],
)

cc_binary(
    name = "empty",
    testonly = True,
    deps = ["//source/toolchain/validation:test"],
)

# This runtime gives the SDK a transitive shared dependency with a distinct
# soname, exercising archive metadata and relocated loading together.
library(
    name = "runtime",
    testonly = True,
    srcs = ["sdk/runtime.c"],
    hdrs = ["sdk/runtime.h"],
    linkage = "shared",
    module = "toolchain_runtime",
    shared_lib_name = select({
        "//:linux": "libruntime.so.1",
        "//:windows": "runtime.dll",
        "//conditions:default": "libruntime.so",
    }),
)

# These variants publish one dependency surface under both linkage models. The
# shared runtime above remains visible in each release graph.
library(
    name = "dependency_static",
    testonly = True,
    srcs = ["sdk/project.c"],
    hdrs = [
        "sdk/private/project_detail.h",
        "sdk/project.h",
    ],
    defines = ["TOOLCHAIN_PROJECT_VALUE=1"],
    includes = ["sdk/private"],
    deps = [":runtime"],
)

library(
    name = "dependency_shared",
    testonly = True,
    srcs = ["sdk/project.c"],
    hdrs = [
        "sdk/private/project_detail.h",
        "sdk/project.h",
    ],
    defines = ["TOOLCHAIN_PROJECT_VALUE=1"],
    includes = ["sdk/private"],
    linkage = "shared",
    deps = [":runtime"],
)

cc_library(
    name = "public",
    hdrs = ["sdk/public.h"],
    defines = ["TOOLCHAIN_TEST_PUBLIC=1"],
)

cc_library(
    name = "api",
    testonly = True,
    hdrs = ["sdk/library.h"],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    deps = [
        ":public",
        "//source:headers",
    ],
)

# Three header components prove declared sibling edges, an external dependency
# and isolation from an unrelated sibling through the same library macro.
library(
    name = "components",
    srcs = [],
    hdrs = glob(["components/**/*.h"]),
    component_deps = {
        "consumer": [":public"],
    },
    components = {
        "consumer": ["foundation"],
        "foundation": [],
        "unrelated": [],
    },
    module = "components",
)

cc_library(
    name = "dependency_api",
    hdrs = ["sdk/project.h"],
    defines = ["TOOLCHAIN_PROJECT_VALUE=1"],
    deps = ["//source:headers"],
)

# The alwayslink archive enters the shared library during its own link. The
# imported interface then carries the completed shared object to consumers.
library(
    name = "private",
    testonly = True,
    srcs = ["sdk/private.c"],
    module = "toolchain_private",
    alwayslink = True,
)

# The static fixture carries unresolved dependency requirements to its final
# consumer and compiles private implementation code into the archive.
library(
    name = "static",
    testonly = True,
    srcs = [
        "sdk/library.c",
        "sdk/library.cpp",
        "sdk/private.c",
    ],
    hdrs = [
        "sdk/library.h",
        "sdk/optional.h",
    ],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    implementation_deps = [":dependency_static"],
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = ["TOOLCHAIN_TEST_PRIVATE=1"],
    module = "toolchain_test",
    deps = [":public"],
)

# The shared fixture embeds its private archive and carries its shared
# dependencies onward as runtime metadata.
library(
    name = "shared",
    testonly = True,
    srcs = [
        "sdk/library.c",
        "sdk/library.cpp",
    ],
    hdrs = [
        "sdk/library.h",
        "sdk/optional.h",
    ],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    implementation_deps = [
        ":dependency_shared",
        ":private",
        ":runtime",
    ],
    linkage = "shared",
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = ["TOOLCHAIN_TEST_PRIVATE=1"],
    module = "toolchain_test",
    deps = [":public"],
)

filegroup(
    name = "binary",
    testonly = True,
    srcs = [":shared_shared"],
)
