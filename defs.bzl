# Copyright (c) 2023-present Matt Kaes and contributors

"""Public build declarations for Toolchain consumers."""

load("//source/bazel:package.bzl", _package = "package")
load("//source/bazel:rules/format.bzl", _format = "format")
load("//source/bazel:rules/library.bzl", _LINUX = "LINUX", _WEB = "WEB", _WINDOWS = "WINDOWS", _library = "library")
load("//source/bazel:rules/project.bzl", _binary = "binary", _component = "component", _project = "project")
load("//source/bazel:rules/validation.bzl", _validation = "validation")
load("//source/bazel:rules/setup.bzl", _setup = "setup")

LINUX = _LINUX
WEB = _WEB
WINDOWS = _WINDOWS
library = _library
binary = _binary
component = _component
project = _project
package = _package
format = _format
validation = _validation
setup = _setup
vscode = _setup
