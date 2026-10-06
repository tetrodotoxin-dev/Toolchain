"""Resolve generated validation SDKs through the candidate Toolchain archive."""

module(
    name = "consumer",
    version = "{version}",
)

bazel_dep(name = "rules_cc", version = "0.2.17")
bazel_dep(name = "tetro_toolchain", version = "{version}")
archive_override(
    module_name = "tetro_toolchain",
    sha256 = "{toolchain_sha256}",
    urls = ["https://github.com/tetrodotoxin-dev/Toolchain/releases/download/v{version}/tetro_toolchain-{version}-source.tar.gz"],
)

register_toolchains(
    "@tetro_toolchain//:cc_toolchain_for_linux_x86_64",
    "@tetro_toolchain//:cc_toolchain_for_windows_x64",
    "@tetro_toolchain//:cc_toolchain_for_wasm32",
)

sdks = use_extension("@tetro_toolchain//source/bazel:sdk.bzl", "dependencies")

# buildifier: disable=no-effect
{dependency_pin}

sdks.release(
    name = "toolchain_test",
    archives = {library_archives},
    implementation_deps = {dependencies},
    linkage = "{linkage}",
    project = "Toolchain",
    version = "{version}",
)
sdks.component(
    name = "api",
    release = "toolchain_test",
    deps = ["@dependency//:api"],
)
use_repo(sdks, "toolchain_test")
