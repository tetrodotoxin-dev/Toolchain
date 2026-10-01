module(name = "sdk_consumer")

bazel_dep(name = "rules_cc", version = "0.2.17")
bazel_dep(name = "tetro_toolchain", version = "{version}")
archive_override(
    module_name = "tetro_toolchain",
    sha256 = "{toolchain_sha256}",
    urls = ["https://github.com/tetrodotoxin-dev/Toolchain/releases/download/v{version}/tetro_toolchain-{version}-source.tar.gz"],
)

register_toolchains("@tetro_toolchain//:cc_toolchain_for_linux_x86_64")

sdks = use_extension("@tetro_toolchain//source/bazel:sdk.bzl", "dependencies")
sdks.release(
    name = "tetro_toolchain",
    project = "Toolchain",
    version = "{version}",
    linkage = "{linkage}",
    archives = {dependency_archives},
)
use_repo(sdks, fixture_dependency = "tetro_toolchain")

sdks.release(
    name = "toolchain_test",
    project = "Toolchain",
    version = "{version}",
    linkage = "{linkage}",
    archives = {library_archives},
    deps = ["@fixture_dependency//:tetro_toolchain"],
)
use_repo(sdks, "toolchain_test")
