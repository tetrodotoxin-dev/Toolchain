"""Resolve every SDK variant from fixed release pins."""

module(name = "consumer", version = "{version}")

bazel_dep(name = "tetro_toolchain", version = "{version}")
bazel_dep(name = "rules_cc", version = "0.2.17")
archive_override(
    module_name = "tetro_toolchain",
    sha256 = "{toolchain_sha256}",
    urls = ["https://github.com/tetrodotoxin-dev/Toolchain/releases/download/v{version}/tetro_toolchain-{version}-source.tar.gz"],
)

sdks = use_extension("@tetro_toolchain//source/bazel:sdk.bzl", "dependencies")

sdks.release(
    name = "dependency_static", library = "tetro_toolchain", linkage = "static",
    archives = {dependency_archives}, project = "Toolchain", version = "{version}",
)
sdks.release(
    name = "dependency_shared", library = "tetro_toolchain", linkage = "shared",
    archives = {dependency_archives}, project = "Toolchain", version = "{version}",
)

sdks.release(
    name = "matching_static", library = "toolchain_test", linkage = "static",
    archives = {matching_archives}, project = "Toolchain", version = "{version}",
    implementation_deps = ["@dependency_static//:tetro_toolchain"],
)
sdks.component(name = "api", release = "matching_static", deps = ["@dependency_static//:api"])
sdks.release(
    name = "matching_shared", library = "toolchain_test", linkage = "shared",
    archives = {matching_archives}, project = "Toolchain", version = "{version}",
    implementation_deps = ["@dependency_shared//:tetro_toolchain"],
)
sdks.component(name = "api", release = "matching_shared", deps = ["@dependency_shared//:api"])
sdks.release(
    name = "mixed_static", library = "toolchain_test", linkage = "static",
    archives = {mixed_archives}, project = "Toolchain", version = "{version}",
    implementation_deps = ["@dependency_shared//:tetro_toolchain"],
)
sdks.component(name = "api", release = "mixed_static", deps = ["@dependency_shared//:api"])
sdks.release(
    name = "mixed_shared", library = "toolchain_test", linkage = "shared",
    archives = {mixed_archives}, project = "Toolchain", version = "{version}",
)
sdks.component(name = "api", release = "mixed_shared", deps = ["@dependency_static//:api"])

sdks.release(
    name = "matching_standalone", library = "toolchain_test", linkage = "static",
    archives = {matching_archives}, project = "Toolchain", version = "{version}",
)
sdks.release(
    name = "mixed_standalone", library = "toolchain_test", linkage = "static",
    archives = {mixed_archives}, project = "Toolchain", version = "{version}",
)

sdks.release(
    name = "bad_static", library = "tetro_toolchain", linkage = "static",
    archives = {bad_static_archives}, project = "Toolchain", version = "{version}",
)
sdks.release(
    name = "bad_shared", library = "tetro_toolchain", linkage = "shared",
    archives = {bad_shared_archives}, project = "Toolchain", version = "{version}",
)
sdks.release(
    name = "bad_component", library = "tetro_toolchain", linkage = "static",
    archives = {bad_component_archives}, project = "Toolchain", version = "{version}",
)
sdks.release(
    name = "conflict_archive", library = "toolchain_test", linkage = "static",
    archives = {matching_archives}, project = "Toolchain", version = "{version}",
    implementation_deps = ["@bad_static//:tetro_toolchain"],
)
sdks.release(
    name = "conflict_runtime", library = "toolchain_test", linkage = "static",
    archives = {mixed_archives}, project = "Toolchain", version = "{version}",
    implementation_deps = ["@bad_shared//:tetro_toolchain"],
)
sdks.release(
    name = "conflict_component", library = "toolchain_test", linkage = "shared",
    archives = {mixed_archives}, project = "Toolchain", version = "{version}",
)
sdks.component(name = "api", release = "conflict_component", deps = ["@bad_component//:api"])
sdks.release(
    name = "missing_variant", library = "toolchain_test", linkage = "shared",
    archives = {missing_archives}, project = "Toolchain", version = "{version}",
)

use_repo(
    sdks,
    "dependency_static", "dependency_shared",
    "matching_static", "matching_shared", "mixed_static", "mixed_shared",
    "matching_standalone", "mixed_standalone",
    "bad_static", "bad_shared", "bad_component",
    "conflict_archive", "conflict_runtime", "conflict_component", "missing_variant",
)
