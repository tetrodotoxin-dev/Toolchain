module(name = "example")
sdks = use_extension("@tetro_toolchain//source/bazel:sdk.bzl", "dependencies")
sdks.release(name = "runtime", project = "Runtime")
sdks.release(name = "foundation", project = "Foundation")
