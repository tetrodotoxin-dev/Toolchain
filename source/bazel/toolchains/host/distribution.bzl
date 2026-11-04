# Copyright (c) 2023-present Matt Kaes and contributors

"""Cache the pinned LLVM files independently of host configuration."""

load("//source:sdk/normalize.bzl", "copy_tool")

_VERSION = "22.1.8"
_RELEASE = "llvm-22.1.8-2"
_DISTRIBUTIONS = {
    "linux": (
        "linux-amd64-musl",
        "7e40cc03fec925670e478abf1bf432918e7c8ef745941dbb23abbd860386f265",
    ),
    "windows": (
        "windows-amd64",
        "5db93697f379d76fa8c97e17a9359f4e7458f0a15d8d03a7e2254a14d660a250",
    ),
}

def _llvm(ctx):
    system = ctx.os.name.lower()
    system = "windows" if "windows" in system else system
    if system not in _DISTRIBUTIONS or ctx.os.arch not in ("amd64", "x86_64"):
        fail("LLVM acquisition currently supports Linux and Windows x86_64 hosts")

    override = ctx.os.environ.get("BAZEL_LLVM")
    if override:
        ctx.symlink(ctx.path(override), "llvm")
    else:
        host, checksum = _DISTRIBUTIONS[system]
        ctx.download_and_extract(
            url = "https://github.com/hermeticbuild/hermetic-llvm/releases/download/" +
                  _RELEASE +
                  "/llvm-toolchain-minimal-" +
                  _VERSION +
                  "-" +
                  host +
                  ".tar.zst",
            sha256 = checksum,
            output = "llvm",
        )

        suffix = ".exe" if system == "windows" else ""
        if not ctx.path("llvm/bin/llvm-lib" + suffix).exists:
            copy_tool(ctx, "llvm/bin/llvm-ar" + suffix, "llvm/bin/llvm-lib" + suffix)

    ctx.template("BUILD.bazel", ctx.attr._build)
    return ctx.repo_metadata(reproducible = not override)

llvm_distribution = repository_rule(
    implementation = _llvm,
    attrs = {
        "_build": attr.label(
            default = Label("//source/bazel:toolchains/host/distribution.build"),
        ),
    },
    environ = ["BAZEL_LLVM"],
)
