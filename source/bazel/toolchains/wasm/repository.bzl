# Copyright (c) 2023-present Matt Kaes and contributors

"""Pinned Emscripten inputs for hosted modules and validation runners."""

load("//source:sdk/normalize.bzl", "copy_tool")

_EMSCRIPTEN_RELEASE = "c387d7a7e9537d0041d2c3ae71b7538cc978104e"
_NODE_VERSION = "22.16.0"

_EMSCRIPTEN = {
    "linux": struct(platform = "linux", archive = "tar.xz", sha256 = "a06e7ddda0c168f7ad52e6e0509c98db3545dcb254d3b9052e9e6b8423eaee7d"),
    "windows": struct(platform = "win", archive = "zip", sha256 = "388e9fab2bc9f94e85b1541e6ae0f1d9a5b9dfa9d756d89a0a3fc7acc052fbd5"),
}
_NODE = {
    "linux": struct(platform = "linux-x64", archive = "tar.xz", sha256 = "f4cb75bb036f0d0eddf6b79d9596df1aaab9ddccd6a20bf489be5abe9467e84e"),
    "windows": struct(platform = "win-x64", archive = "zip", sha256 = "21c2d9735c80b8f86dab19305aa6a9f6f59bbc808f68de3eef09d5832e3bfbbd"),
}

def _host(ctx):
    """Select the runner distribution for a supported execution host."""
    system = ctx.os.name.lower()
    system = "windows" if "windows" in system else system
    if system not in _EMSCRIPTEN or ctx.os.arch not in ("amd64", "x86_64"):
        fail("standalone Web validation supports Linux and Windows x86_64 hosts")
    return system

def _download_emscripten(ctx, host, strip_prefix):
    """Share the SDK release pin between headers and executable tool bundles."""
    pin = _EMSCRIPTEN[host]
    ctx.download_and_extract(
        url = "https://storage.googleapis.com/webassembly/emscripten-releases-builds/" + pin.platform + "/" + _EMSCRIPTEN_RELEASE + "/wasm-binaries." + pin.archive,
        sha256 = pin.sha256,
        strip_prefix = strip_prefix,
    )

def _sysroot(ctx):
    """Extract the pinned Emscripten headers into a Bazel repository.

    Args:
        ctx: Repository context used to download and expose the headers.
    """

    # The sysroot archive contributes target headers. The selected LLVM
    # distribution contributes the compiler, linker and resource headers.
    _download_emscripten(ctx, "linux", "install/emscripten/cache/sysroot/include")
    ctx.template("BUILD", ctx.attr._build)
    return ctx.repo_metadata(reproducible = True)

emscripten_sysroot = repository_rule(
    implementation = _sysroot,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/wasm/sysroot.build")),
    },
)

def _sdk(ctx):
    """Extract the complete pinned Emscripten SDK for validation runners.

    Ordinary Web libraries use the smaller header repository and direct LLVM
    toolchain. Standalone validation additionally needs Emscripten's JavaScript
    runtime and system libraries.

    Args:
        ctx: Repository context receiving the pinned SDK.
    """
    host = _host(ctx)
    windows = host == "windows"
    _download_emscripten(ctx, host, "install")
    suffix = ".exe" if windows else ""
    # Some bundles omit Clang's preprocessor alias. Clang selects that mode
    # from its filename, so expose the same tool in either host distribution.
    if not ctx.path("bin/clang-cpp" + suffix).exists:
        copy_tool(ctx, "bin/clang" + suffix, "bin/clang-cpp" + suffix)
    if windows:
        # Keep Python imports from modifying the downloaded repository. The
        # toolchain supplies the selected interpreter through EMSDK_PYTHON.
        ctx.template("em++.bat", ctx.attr._driver)
    ctx.template("emscripten/.emscripten", ctx.attr._configuration)
    ctx.template("BUILD.bazel", ctx.attr._build)
    return ctx.repo_metadata(reproducible = True)

emscripten_sdk = repository_rule(
    implementation = _sdk,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/wasm/sdk.build")),
        "_driver": attr.label(default = Label("//source/bazel:toolchains/wasm/emscripten.cmd")),
        "_configuration": attr.label(default = Label("//source/bazel:toolchains/wasm/emscripten.py")),
    },
)

def _node(ctx):
    """Acquire the Node runtime used to execute Web validation programs.

    Args:
        ctx: Repository context receiving the pinned runtime.
    """
    pin = _NODE[_host(ctx)]
    distribution = "node-v" + _NODE_VERSION + "-" + pin.platform
    ctx.download_and_extract(
        url = "https://nodejs.org/dist/v" + _NODE_VERSION + "/" + distribution + "." + pin.archive,
        sha256 = pin.sha256,
        strip_prefix = distribution,
    )
    ctx.template("BUILD.bazel", ctx.attr._build)
    return ctx.repo_metadata(reproducible = True)

emscripten_node = repository_rule(
    implementation = _node,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/wasm/node.build")),
    },
)
