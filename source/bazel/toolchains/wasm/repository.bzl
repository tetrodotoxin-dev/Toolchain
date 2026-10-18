# Copyright (c) 2023-present Matt Kaes and contributors

"""Pinned Emscripten inputs for hosted modules and validation runners."""

_EMSCRIPTEN_URL = "https://storage.googleapis.com/webassembly/emscripten-releases-builds/linux/c387d7a7e9537d0041d2c3ae71b7538cc978104e/wasm-binaries.tar.xz"
_EMSCRIPTEN_SHA256 = "a06e7ddda0c168f7ad52e6e0509c98db3545dcb254d3b9052e9e6b8423eaee7d"
_NODE_URL = "https://nodejs.org/dist/v22.16.0/node-v22.16.0-linux-x64.tar.xz"
_NODE_SHA256 = "f4cb75bb036f0d0eddf6b79d9596df1aaab9ddccd6a20bf489be5abe9467e84e"

def _sysroot(ctx):
    """Extract the pinned Emscripten headers into a Bazel repository.

    Args:
        ctx: Repository context used to download and expose the headers.
    """

    # The sysroot archive contributes target headers. The selected LLVM
    # distribution contributes the compiler, linker and resource headers.
    ctx.download_and_extract(
        url = _EMSCRIPTEN_URL,
        sha256 = _EMSCRIPTEN_SHA256,
        strip_prefix = "install/emscripten/cache/sysroot/include",
    )
    ctx.template("BUILD", ctx.attr._build)

emscripten_sysroot = repository_rule(
    implementation = _sysroot,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/wasm/sysroot.BUILD.tpl")),
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
    if ctx.os.name.lower() != "linux" or ctx.os.arch not in ("amd64", "x86_64"):
        fail("standalone Web validation currently supports Linux x86_64 hosts")
    ctx.download_and_extract(
        url = _EMSCRIPTEN_URL,
        sha256 = _EMSCRIPTEN_SHA256,
        strip_prefix = "install",
    )
    ctx.file(
        "emscripten/.emscripten",
        """import os

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BINARYEN_ROOT = ROOT_DIR
LLVM_ROOT = os.path.join(ROOT_DIR, "bin")
NODE_JS = "node"
FROZEN_CACHE = True
""",
    )
    ctx.template("BUILD.bazel", ctx.attr._build)

emscripten_sdk = repository_rule(
    implementation = _sdk,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/wasm/sdk.BUILD.tpl")),
    },
)

def _node(ctx):
    """Acquire the Node runtime used to execute Web validation programs.

    Args:
        ctx: Repository context receiving the pinned runtime.
    """
    if ctx.os.name.lower() != "linux" or ctx.os.arch not in ("amd64", "x86_64"):
        fail("standalone Web validation currently supports Linux x86_64 hosts")
    ctx.download_and_extract(
        url = _NODE_URL,
        sha256 = _NODE_SHA256,
        strip_prefix = "node-v22.16.0-linux-x64",
    )
    ctx.template("BUILD.bazel", ctx.attr._build)

emscripten_node = repository_rule(
    implementation = _node,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/wasm/node.BUILD.tpl")),
    },
)
