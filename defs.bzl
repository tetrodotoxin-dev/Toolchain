# Copyright (c) 2023-present Matt Kaes and contributors

"""Public build declarations for Toolchain consumers."""

load("//source/bazel:package.bzl", _package = "package")
load("//source/bazel:rules/format.bzl", _format = "format")
load("//source/bazel:rules/library.bzl", _LINUX = "LINUX", _WEB = "WEB", _WINDOWS = "WINDOWS", _library = "library")
load("//source/bazel:rules/snapshot.bzl", _snapshot = "snapshot")
load("//source/bazel:rules/validation.bzl", _validation = "validation")
load("//source/bazel:rules/vscode.bzl", _vscode = "vscode")

LINUX = _LINUX
WEB = _WEB
WINDOWS = _WINDOWS
library = _library
package = _package
format = _format
snapshot = _snapshot
validation = _validation
vscode = _vscode
