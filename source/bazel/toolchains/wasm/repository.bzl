# Copyright (c) 2023-present Matt Kaes and contributors

"""Pinned Emscripten inputs for hosted modules and validation runners."""

_EMSCRIPTEN_URL = "https://storage.googleapis.com/webassembly/emscripten-releases-builds/linux/c387d7a7e9537d0041d2c3ae71b7538cc978104e/wasm-binaries.tar.xz"
_EMSCRIPTEN_SHA256 = "a06e7ddda0c168f7ad52e6e0509c98db3545dcb254d3b9052e9e6b8423eaee7d"
_EMSCRIPTEN_WINDOWS_URL = "https://storage.googleapis.com/webassembly/emscripten-releases-builds/win/c387d7a7e9537d0041d2c3ae71b7538cc978104e/wasm-binaries.zip"
_EMSCRIPTEN_WINDOWS_SHA256 = "388e9fab2bc9f94e85b1541e6ae0f1d9a5b9dfa9d756d89a0a3fc7acc052fbd5"
_NODE_URL = "https://nodejs.org/dist/v22.16.0/node-v22.16.0-linux-x64.tar.xz"
_NODE_SHA256 = "f4cb75bb036f0d0eddf6b79d9596df1aaab9ddccd6a20bf489be5abe9467e84e"
_NODE_WINDOWS_URL = "https://nodejs.org/dist/v22.16.0/node-v22.16.0-win-x64.zip"
_NODE_WINDOWS_SHA256 = "21c2d9735c80b8f86dab19305aa6a9f6f59bbc808f68de3eef09d5832e3bfbbd"

def _windows(ctx):
    """Select the runner distribution for a supported execution host."""
    system = ctx.os.name.lower()
    if (system != "linux" and "windows" not in system) or ctx.os.arch not in ("amd64", "x86_64"):
        fail("standalone Web validation supports Linux and Windows x86_64 hosts")
    return "windows" in system

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
    windows = _windows(ctx)
    ctx.download_and_extract(
        url = _EMSCRIPTEN_WINDOWS_URL if windows else _EMSCRIPTEN_URL,
        sha256 = _EMSCRIPTEN_WINDOWS_SHA256 if windows else _EMSCRIPTEN_SHA256,
        strip_prefix = "install",
    )
    if windows:
        # The Windows archive omits Clang's preprocessor alias. Its executable
        # selects that mode from the clang-cpp filename.
        ctx.symlink(ctx.path("bin/clang.exe"), "bin/clang-cpp.exe")
        # Keep Python imports from modifying the downloaded repository. The
        # toolchain supplies the selected interpreter through EMSDK_PYTHON.
        ctx.file("em++.bat", '@"%EMSDK_PYTHON%" -B "%~dp0emscripten\\em++.py" %*\r\n@exit /b %errorlevel%\r\n')
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
    ctx.template("BUILD.bazel", ctx.attr._build, substitutions = {
        "__ROOT__": json.encode(str(ctx.path(".")).replace("\\", "/")),
    })

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
    windows = _windows(ctx)
    ctx.download_and_extract(
        url = _NODE_WINDOWS_URL if windows else _NODE_URL,
        sha256 = _NODE_WINDOWS_SHA256 if windows else _NODE_SHA256,
        strip_prefix = "node-v22.16.0-win-x64" if windows else "node-v22.16.0-linux-x64",
    )
    ctx.template("BUILD.bazel", ctx.attr._build, substitutions = {
        "__NODE__": "node.exe" if windows else "bin/node",
    })

emscripten_node = repository_rule(
    implementation = _node,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/wasm/node.BUILD.tpl")),
    },
)
