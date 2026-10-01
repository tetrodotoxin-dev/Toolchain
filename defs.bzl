# Copyright (c) 2023-present Matt Kaes and contributors

"""Public build declarations for Toolchain consumers."""

load("//source/bazel:library.bzl", _LINUX = "LINUX", _WEB = "WEB", _WINDOWS = "WINDOWS", _library = "library")
load("//source/bazel:package.bzl", _package = "package")
load("//source/bazel:validation.bzl", _benchmarks = "benchmarks", _tests = "tests")
load("//source/bazel:vscode.bzl", _vscode = "vscode")

LINUX = _LINUX
WEB = _WEB
WINDOWS = _WINDOWS
library = _library
package = _package
benchmarks = _benchmarks
tests = _tests
vscode = _vscode
