load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//:defs.bzl", "library")

package(default_visibility = [
    "//:__pkg__",
    "//validation/integration:__pkg__",
    "//validation/integration/linkage:__pkg__",
])

exports_files([
    "comment_quality/corpus.jsonl",
    "harness/reporting.cpp",
    "sdk/consumer.c",
    "sdk/dependency.c",
    "sdk/style.cpp",
    "sdk/web_benchmark.cpp",
    "sdk/web_test.cpp",
] + glob(["sdk/*.tpl"]))

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

# The host supplies the runtime separately from the SDK's link interface.
library(
    name = "system_host",
    testonly = True,
    srcs = ["sdk/host.c"],
    hdrs = ["sdk/host.h"],
    linkage = "shared",
    module = "toolchain_host",
    shared_lib_name = select({
        "//:windows": "system_host.dll",
        "//conditions:default": "libsystem_host.so.1",
    }),
    user_link_flags = select({
        "//:linux": ["-Wl,-soname,libsystem_host.so.1"],
        "//conditions:default": [],
    }),
)

filegroup(
    name = "system_host_binary",
    testonly = True,
    srcs = [":system_host_shared"],
)

# A Linux link interface has the runtime's SONAME but a distinct filename.
# Relocated consumers must find the host runtime, even with this file present.
genrule(
    name = "system_host_stub",
    testonly = True,
    srcs = [":system_host_shared"],
    outs = ["link/libsystem_host.so"],
    cmd = "cp $(location :system_host_shared) $@",
)

cc_import(
    name = "system_host_import",
    testonly = True,
    hdrs = ["sdk/host.h"],
    interface_library = select({
        "//:windows": ":system_host_interface",
        "//conditions:default": ":system_host_stub",
    }),
    linkopts = select({
        "//:linux": ["-Wl,--undefined=toolchain_host_entry"],
        "//conditions:default": [],
    }),
    system_provided = True,
)

_HOST = select({
    "//:linux": [":system_host_import"],
    "//:windows": [":system_host_import"],
    "//conditions:default": [],
})

# This runtime gives the SDK a transitive shared dependency with a distinct
# soname, exercising archive metadata and relocated loading together.
library(
    name = "runtime",
    testonly = True,
    srcs = [
        "sdk/registration.cpp",
        "sdk/runtime.c",
    ],
    hdrs = ["sdk/runtime.h"],
    linkage = "shared",
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_archive_probe"],
        "//conditions:default": [],
    }),
    module = "toolchain_runtime",
    shared_lib_name = select({
        "//:linux": "libruntime.so.1",
        "//:windows": "runtime.dll",
        "//conditions:default": "libruntime.so",
    }),
    deps = _HOST,
)

library(
    name = "runtime_static",
    testonly = True,
    srcs = [
        "sdk/registration.cpp",
        "sdk/runtime.c",
    ],
    hdrs = ["sdk/runtime.h"],
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_archive_probe"],
        "//conditions:default": [],
    }),
    module = "toolchain_runtime",
    deps = _HOST,
    alwayslink = True,
)

# The plugin supplies its callable only through runtime symbol lookup.
library(
    name = "plugin",
    testonly = True,
    srcs = ["sdk/plugin.c"],
    linkage = "shared",
    module = "toolchain_plugin",
)

# The consumer loads this DLL by name. Importing only the DLL reproduces a
# runtime dependency whose distribution supplies no linker interface.
cc_import(
    name = "plugin_import",
    testonly = True,
    shared_library = ":plugin_shared",
)

# Each dependency variant chooses its matching runtime through ordinary deps.
# The final SDK must retain that choice across the second library boundary.
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
    deps = [":runtime_static"] + select({
        "//:windows": [":plugin_import"],
        "//conditions:default": [],
    }),
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
    deps = [":runtime"] + select({
        "//:windows": [":plugin_import"],
        "//conditions:default": [],
    }),
)

cc_library(
    name = "public",
    hdrs = ["sdk/public.h"],
    defines = ["TOOLCHAIN_TEST_PUBLIC=1"],
)

cc_library(
    name = "api",
    testonly = True,
    hdrs = [
        "sdk/library.h",
        "sdk/private/library_detail.h",
    ],
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
        "sdk/private/library_detail.h",
    ],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    implementation_deps = [":dependency_static"],
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = [
        "TOOLCHAIN_TEST_PRIVATE=1",
        "EXPECT_PROJECT_STATIC=1",
    ],
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
        "sdk/private/library_detail.h",
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
    local_defines = [
        "TOOLCHAIN_TEST_PRIVATE=1",
        "EXPECT_PROJECT_STATIC=0",
    ],
    module = "toolchain_test",
    deps = [":public"],
)

# Mixed choices exercise independent output and dependency linkage. The shared
# variant absorbs its static dependencies; the static variant keeps the shared
# dependency's DLL or SO available to the final consumer.
library(
    name = "shared_static",
    testonly = True,
    srcs = [
        "sdk/library.c",
        "sdk/library.cpp",
    ],
    hdrs = [
        "sdk/library.h",
        "sdk/optional.h",
        "sdk/private/library_detail.h",
    ],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    implementation_deps = [
        ":dependency_static",
        ":private",
    ],
    linkage = "shared",
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = [
        "TOOLCHAIN_TEST_PRIVATE=1",
        "EXPECT_PROJECT_STATIC=1",
    ],
    module = "toolchain_test",
    deps = [":public"],
)

library(
    name = "static_shared",
    testonly = True,
    srcs = [
        "sdk/library.c",
        "sdk/library.cpp",
        "sdk/private.c",
    ],
    hdrs = [
        "sdk/library.h",
        "sdk/optional.h",
        "sdk/private/library_detail.h",
    ],
    defines = ["TOOLCHAIN_TEST_VALUE=21"],
    implementation_deps = [":dependency_shared"],
    linkopts = select({
        "//:linux": ["-Wl,--wrap=toolchain_link_probe"],
        "//conditions:default": [],
    }),
    local_defines = [
        "TOOLCHAIN_TEST_PRIVATE=1",
        "EXPECT_PROJECT_STATIC=0",
    ],
    module = "toolchain_test",
    deps = [":public"],
)

filegroup(
    name = "binary",
    testonly = True,
    srcs = [":shared_shared"],
)
