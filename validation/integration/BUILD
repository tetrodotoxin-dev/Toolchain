load("@host_tools//:settings.bzl", "CXX", "OBJDUMP")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("//source/bazel:package.bzl", "package_release")
load(":components.bzl", "component_headers")
load(":runner.bzl", "check", "runner")
load(":validation_data.bzl", "validation_data")

package(default_visibility = ["//:__pkg__"])

filegroup(
    name = "validation_test_data",
    srcs = ["sdk.c"],
)

filegroup(
    name = "validation_benchmark_data",
    srcs = ["components.c"],
)

validation_data(
    name = "validation_data",
    testonly = True,
    benchmark_data = ":validation_benchmark_data",
    benchmarks = "//:benchmarks",
    test_data = ":validation_test_data",
    tests = "//:tests",
)

COMMENT_QUALITY = check(
    name = "comment_quality",
    srcs = ["comment_quality.py"],
)

COMPILE_ALLOCATION = check(
    name = "compile_allocation",
    srcs = ["compile_allocation.py"],
    args = [CXX],
)

LIFETIME = check(
    name = "lifetime",
    srcs = ["lifetime.py"],
    args = [CXX],
)

# The reporting fixture exercises every result path through the public runner.
# Its process status and output preserve the contract seen by repository tests.
HARNESS = check(
    name = "harness",
    srcs = ["harness.py"],
    args = [
        ".bin/bin/$(rootpath //:tests)",
        ".bin/bin/$(rootpath //validation/data:reporting)",
        ".bin/bin/$(rootpath //:benchmarks)",
        ".bin/bin/$(rootpath //validation/data:skipped)",
        ".bin/bin/$(rootpath //validation/data:empty)",
    ],
    data = [
        "//:benchmarks",
        "//:tests",
        "//validation/data:empty",
        "//validation/data:reporting",
        "//validation/data:skipped",
    ],
)

FORMAT = check(
    name = "format",
    srcs = ["format.py"],
    data = ["//:format"],
)

# These native leaves prove the component graph and both library linkages in the
# current checkout before archive construction adds another repository boundary.
component_headers(
    name = "component_headers",
    component = "//validation/data:consumer",
    required = [
        "//validation/data:components/consumer/value.h",
        "//validation/data:components/foundation/value.h",
        "//validation/data:sdk/public.h",
    ],
    excluded = ["//validation/data:components/unrelated/value.h"],
)

cc_binary(
    name = "components",
    testonly = True,
    linkstatic = False,
    srcs = ["components.c"],
    deps = [":component_headers"],
)

cc_binary(
    name = "static",
    testonly = True,
    linkstatic = False,
    srcs = ["library.c"],
    deps = [
        "//validation/data:static",
        "//validation/data:system_host",
    ],
)

cc_binary(
    name = "shared",
    testonly = True,
    linkstatic = False,
    srcs = ["library.c"],
    deps = [
        "//validation/data:shared",
        "//validation/data:system_host",
    ],
)

cc_binary(
    name = "symbols",
    testonly = True,
    linkstatic = False,
    srcs = [
        "library.c",
        "symbols.c",
    ],
    deps = [
        "//validation/data:shared",
        "//validation/data:system_host",
    ],
)

SNAPSHOT = check(
    name = "snapshot",
    srcs = ["snapshot.py"],
)

# The primary fixture publishes the component surface and the runtime graph
# consumed by the temporary external workspace.
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
    shared = "//validation/data:shared",
    static = "//validation/data:static",
    tags = ["manual"],
)

# A separate release gives the consumer an explicit SDK dependency. Matching
# runtime payloads then converge through archive metadata during import.
package_release(
    name = "dependency",
    testonly = True,
    component_dependencies = {"api": []},
    components = {"//validation/data:dependency_api": "api"},
    shared = "//validation/data:dependency_shared",
    static = "//validation/data:dependency_static",
    tags = ["manual"],
)

# The checksum output group is the release inventory consumed by sdk.py.
# Like its release input, it stays out of local wildcard builds.
filegroup(
    name = "checksum",
    tags = ["manual"],
    testonly = True,
    srcs = [":fixture"],
    output_group = "checksum",
)

# This test creates a fresh Bazel workspace and consumes the candidate source
# and binary archives through their public module extension. The complete
# platform matrix is explicit, including through the integration suite.
SDK = [
    check(
        name = "sdk" if case == "all" else "sdk_" + case,
        tags = ["manual"],
        main = "sdk.py",
        srcs = ["sdk.py"],
        args = [
            ".bin/bin/$(rootpath //:_candidate_snapshot)",
            ".bin/bin/$(rootpath :checksum)",
            ".bin/bin/$(rootpath //validation/integration/linkage:checksum)",
            ".bin/bin/$(rootpath //validation/data:system_host_binary)",
            OBJDUMP,
            case,
        ],
        data = [
            ":checksum",
            ":dependency",
            ":fixture",
            "//:_candidate_snapshot",
            "//validation/data:system_host_binary",
            "//validation/integration/linkage:checksum",
            "//validation/integration/linkage:fixture",
        ],
    )
    for case in ["all", "matching", "mixed"]
]

# Independent output roots force fresh release and SDK actions. Debug builds
# retain their source records without imposing byte equality on those records.
REPRODUCIBILITY = check(
    name = "reproducibility",
    srcs = ["reproducibility.py"],
    args = [".bin/bin/$(rootpath //:_candidate_snapshot)"],
    data = ["//:_candidate_snapshot"],
    tags = ["manual"],
)

# Web runners build the standalone platform explicitly, even on a native host.
WEB = check(
    name = "web",
    srcs = ["web.py"],
    args = [
        ".bin/bin/$(rootpath //:tests_web)",
        ".bin/bin/$(rootpath //:benchmarks_web)",
        "$(execpath @emscripten_node//:node)",
    ],
    data = [
        "//:tests_web",
        "//:benchmarks_web",
        "@emscripten_node//:node",
    ],
    tags = ["manual"],
)

# This target is the complete process, linkage and packaging boundary for a
# Toolchain checkout. Its leaves stay individually runnable during diagnosis.
runner(
    name = "integration",
    checks = [COMMENT_QUALITY, COMPILE_ALLOCATION, FORMAT, HARNESS, REPRODUCIBILITY, SNAPSHOT, WEB, SDK[0]],
    binaries = [":components", ":shared", ":static", ":symbols"],
    data = [":validation_data"],
)
