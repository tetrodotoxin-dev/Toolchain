load("@host_tools//:settings.bzl", "CXX", "NM")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@rules_python//python:py_test.bzl", "py_test")
load("//source/bazel:package.bzl", "package_release")
load(":components.bzl", "component_headers")
load(":validation_data.bzl", "validation_data_test")

package(default_visibility = ["//:__pkg__"])

filegroup(
    name = "validation_test_data",
    srcs = ["sdk.c"],
)

filegroup(
    name = "validation_benchmark_data",
    srcs = ["components.c"],
)

validation_data_test(
    name = "validation_data",
    benchmark_data = ":validation_benchmark_data",
    benchmarks = "//:benchmarks_binary",
    test_data = ":validation_test_data",
    tests = "//:tests_binary",
)

py_test(
    name = "comment_quality",
    size = "small",
    srcs = ["comment_quality.py"],
    args = [
        "$(rlocationpath //source/bazel:rules/comment_quality.py)",
        "$(rlocationpath //validation/data:comment_quality/corpus.jsonl)",
    ],
    data = [
        "//source/bazel:rules/comment_quality.py",
        "//validation/data:comment_quality/corpus.jsonl",
    ],
    deps = ["@rules_python//python/runfiles"],
)

py_test(
    name = "compile_allocation",
    size = "small",
    srcs = ["compile_allocation.py"],
    args = [
        "$(rlocationpath @host_tools//:llvm/bin/" + CXX.split("/")[-1] + ")",
        "$(rlocationpath //source:compile_allocation_header)",
    ],
    data = [
        "//source:compile_allocation_dependencies",
        "//source:compile_allocation_header",
        "@host_tools//:llvm/bin/" + CXX.split("/")[-1],
    ],
    deps = ["@rules_python//python/runfiles"],
)

py_test(
    name = "lifetime",
    size = "small",
    srcs = ["lifetime.py"],
    args = [
        "$(rlocationpath @host_tools//:llvm/bin/" + CXX.split("/")[-1] + ")",
        "$(rlocationpath //source:compile_allocation_header)",
    ],
    data = [
        "//source:compile_allocation_dependencies",
        "//source:compile_allocation_header",
        "@host_tools//:llvm/bin/" + CXX.split("/")[-1],
    ],
    deps = ["@rules_python//python/runfiles"],
)

# The reporting fixture exercises every result path through the public runner.
# Its process status and output preserve the contract seen by repository tests.
py_test(
    name = "harness",
    size = "small",
    srcs = ["harness.py"],
    args = [
        "$(rlocationpath //:tests)",
        "$(rlocationpath //validation/data:reporting)",
        "$(rlocationpath //:benchmarks)",
        "$(rlocationpath //validation/data:skipped)",
        "$(rlocationpath //validation/data:empty)",
        "$(rlocationpath //validation/data:harness/reporting.cpp)",
    ],
    data = [
        "//:benchmarks",
        "//:tests",
        "//validation/data:empty",
        "//validation/data:harness/reporting.cpp",
        "//validation/data:reporting",
        "//validation/data:skipped",
    ],
    deps = ["@rules_python//python/runfiles"],
)

py_test(
    name = "format",
    size = "small",
    srcs = ["format.py"],
    args = ["$(rlocationpath //:format)"],
    data = ["//:format"],
    deps = ["@rules_python//python/runfiles"],
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

cc_test(
    name = "components",
    size = "small",
    srcs = ["components.c"],
    deps = [":component_headers"],
)

cc_test(
    name = "static",
    size = "small",
    srcs = ["library.c"],
    deps = [
        "//validation/data:static",
        "//validation/data:system_host",
    ],
)

cc_test(
    name = "shared",
    size = "small",
    srcs = ["library.c"],
    deps = [
        "//validation/data:shared",
        "//validation/data:system_host",
    ],
)

py_test(
    name = "symbols",
    size = "small",
    srcs = ["symbols.py"],
    args = [
        "$(rlocationpath @host_tools//:llvm/bin/" + NM.split("/")[-1] + ")",
        "$(rlocationpath :shared)",
        "$(rlocationpath //validation/data:binary)",
    ],
    data = [
        ":shared",
        "//validation/data:binary",
        "@host_tools//:llvm/bin/" + NM.split("/")[-1],
    ],
    deps = ["@rules_python//python/runfiles"],
)

py_test(
    name = "snapshot",
    size = "small",
    srcs = ["snapshot.py"],
    args = [
        "$(rlocationpath //:snapshot)",
        module_version(),
    ],
    data = ["//:snapshot"],
    deps = ["@rules_python//python/runfiles"],
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
py_test(
    name = "sdk",
    tags = ["manual"],
    size = "medium",
    srcs = ["sdk.py"],
    args = [
        "$(rlocationpath //:_candidate_snapshot)",
        "$(rlocationpath :checksum)",
        "$(rlocationpath //validation/integration/linkage:checksum)",
        "$(rlocationpath //validation/data:system_host_binary)",
    ],
    data = [
        "sdk.c",
        ":checksum",
        ":dependency",
        ":fixture",
        "//:_candidate_snapshot",
        "//validation/data:sdk/BUILD.tpl",
        "//validation/data:sdk/MODULE.tpl",
        "//validation/data:sdk/multiple.tpl",
        "//validation/data:sdk/consumer.c",
        "//validation/data:sdk/dependency.c",
        "//validation/data:sdk/dependency.tpl",
        "//validation/data:sdk/source.tpl",
        "//validation/data:sdk/style.cpp",
        "//validation/data:sdk/web_benchmark.cpp",
        "//validation/data:sdk/web_test.cpp",
        "//validation/data:system_host_binary",
        "//validation/integration/linkage:checksum",
        "//validation/integration/linkage:fixture",
    ],
    deps = ["@rules_python//python/runfiles"],
)

# This target is the complete process, linkage and packaging boundary for a
# Toolchain checkout. Its leaves stay individually runnable during diagnosis.
test_suite(
    name = "integration",
    tags = ["manual"],
    tests = [
        ":comment_quality",
        ":compile_allocation",
        ":components",
        ":format",
        ":harness",
        ":sdk",
        ":shared",
        ":snapshot",
        ":static",
        ":symbols",
        ":validation_data",
    ],
)
