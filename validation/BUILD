load("@host_tools//:settings.bzl", "NM")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@rules_python//python:py_test.bzl", "py_test")
load("//:defs.bzl", "benchmarks", "tests")
load("//source/bazel:package.bzl", "package_release")

package(default_visibility = ["//:__pkg__"])

tests()

benchmarks()

filegroup(
    name = "sources",
    srcs = glob([
        "benchmarks/**",
        "integration/**",
        "tests/**",
    ]) + [
        "BUILD",
        "//validation/data:sources",
    ],
)

# The reporting fixture exercises every result path through the public runner.
# Its process status and output preserve the contract seen by repository tests.
py_test(
    name = "harness",
    size = "small",
    srcs = ["integration/harness.py"],
    args = [
        "$(rlocationpath :tests)",
        "$(rlocationpath //validation/data:reporting)",
        "$(rlocationpath :benchmarks)",
        "$(rlocationpath //validation/data:skipped)",
        "$(rlocationpath //validation/data:empty)",
        "$(rlocationpath //validation/data:harness/reporting.cpp)",
    ],
    data = [
        ":benchmarks",
        ":tests",
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
    srcs = ["integration/format.py"],
    args = ["$(rlocationpath //:format)"],
    data = ["//:format"],
    deps = ["@rules_python//python/runfiles"],
)

# These native leaves prove the component graph and both library linkages in the
# current checkout before archive construction adds another repository boundary.
cc_test(
    name = "components",
    size = "small",
    srcs = ["integration/components.c"],
    deps = ["//validation/data:consumer"],
)

cc_test(
    name = "static",
    size = "small",
    srcs = ["integration/library.c"],
    deps = ["//validation/data:static"],
)

cc_test(
    name = "shared",
    size = "small",
    srcs = ["integration/library.c"],
    deps = ["//validation/data:shared"],
)

py_test(
    name = "symbols",
    size = "small",
    srcs = ["integration/symbols.py"],
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
    sources = [":sources"],
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
    sources = [":sources"],
    static = "//validation/data:dependency_static",
    tags = ["manual"],
)

# The checksum output group is the release inventory consumed by sdk.py.
filegroup(
    name = "checksum",
    testonly = True,
    srcs = [":fixture"],
    output_group = "checksum",
)

# This test creates a fresh Bazel workspace and consumes the candidate source
# and binary archives through their public module extension.
py_test(
    name = "sdk",
    size = "large",
    srcs = ["integration/sdk.py"],
    args = [
        "$(rlocationpath //:sdk)",
        "$(rlocationpath :checksum)",
    ],
    data = [
        "integration/sdk.c",
        ":checksum",
        ":dependency",
        ":fixture",
        "//:sdk",
        "//validation/data:sdk/BUILD.tpl",
        "//validation/data:sdk/MODULE.tpl",
        "//validation/data:sdk/dependency.tpl",
        "//validation/data:sdk/source.tpl",
        "//validation/data:sdk/style.cpp",
    ],
    deps = ["@rules_python//python/runfiles"],
)

# This target is the complete process, linkage and packaging boundary for a
# Toolchain checkout. Its leaves stay individually runnable during diagnosis.
test_suite(
    name = "integration",
    tests = [
        ":components",
        ":format",
        ":harness",
        ":sdk",
        ":shared",
        ":static",
        ":symbols",
    ],
)
