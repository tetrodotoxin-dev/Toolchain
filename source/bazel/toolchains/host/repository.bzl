# Copyright (c) 2023-present Matt Kaes and contributors

"""Supply one LLVM distribution for the execution host and every target.

Bazel verifies and caches the pinned archive. BAZEL_LLVM is the explicit local
installation override used for compiler development. Target SDKs remain
separate inputs because the host chooses which tools run, while the target
chooses the headers and libraries they consume.
"""

_VERSION = "22.1.8"
_RELEASE = "llvm-22.1.8-2"

# These bundles own compiler executables, while each target toolchain selects
# its runtime separately. Static Linux executables run on the supported host
# directly.
_DISTRIBUTIONS = {
    "linux": ("linux-amd64-musl", "7e40cc03fec925670e478abf1bf432918e7c8ef745941dbb23abbd860386f265"),
    "windows": ("windows-amd64", "5db93697f379d76fa8c97e17a9359f4e7458f0a15d8d03a7e2254a14d660a250"),
}

def _host(ctx):
    """Acquire host LLVM tools and publish their paths in settings.bzl.

    Args:
        ctx: Repository context supplying the host platform and environment.
    """
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
            url = "https://github.com/hermeticbuild/hermetic-llvm/releases/download/" + _RELEASE + "/llvm-toolchain-minimal-" + _VERSION + "-" + host + ".tar.zst",
            sha256 = checksum,
            output = "llvm",
        )
    suffix = ".exe" if system == "windows" else ""
    executables = {
        "CXX": "clang++",
        "CLANG": "clang-cl",
        "CPP": "clang-cpp",
        "LINKER": "lld-link",
        "ELF_LINKER": "ld.lld",
        "WASM_LINKER": "wasm-ld",
        "ARCHIVER": "llvm-lib",
        "AR": "llvm-ar",
        "NM": "llvm-nm",
        "OBJDUMP": "llvm-objdump",
        "STRIP": "llvm-strip",
        "COV": "llvm-cov",
    }
    values = {"HOST_SYSTEM": system}
    files = []
    for name, executable in executables.items():
        location = "llvm/bin/" + executable + suffix
        selected = ctx.path(location)

        # llvm-ar implements MSVC library mode under the llvm-lib name. A local
        # alias supplies that stable path while preserving an explicit LLVM
        # installation exactly as selected.
        if executable == "llvm-lib" and not selected.exists:
            location = "llvm-lib" + suffix
            ctx.symlink(ctx.path("llvm/bin/llvm-ar" + suffix), location)
            selected = ctx.path(location)
        if not selected.exists:
            fail("LLVM installation is missing " + str(selected))
        values[name] = str(selected).replace("\\", "/")
        files.extend([location, "llvm/bin/" + selected.realpath.basename])
    resource = ctx.execute([values["CXX"], "-print-resource-dir"])
    if resource.return_code:
        fail(resource.stderr)

    values["RESOURCE_INCLUDE"] = resource.stdout.strip().replace("\\", "/") + "/include"
    python = ctx.which("python" if system == "windows" else "python3")
    if not python:
        fail("Python is required for packaging and export generation")

    values["PYTHON"] = str(python).replace("\\", "/")
    values["PATH"] = ctx.os.environ.get("PATH", "")
    values["TEMP"] = ctx.os.environ.get("TEMP", "/tmp")
    substitutions = {
        '"__' + name + '__"': json.encode(value)
        for name, value in values.items()
    }
    tools = sorted({file: True for file in files})
    substitutions['["__TOOLS__"]'] = repr(tools)
    ctx.template("settings.bzl", ctx.attr._settings, substitutions = substitutions)

    # Individual labels give tests exact executable runfiles; compiler actions
    # receive the complete files group generated from TOOLS.
    ctx.template("BUILD.bazel", ctx.attr._build)

host_tools = repository_rule(
    implementation = _host,
    attrs = {
        "_build": attr.label(default = Label("//source/bazel:toolchains/host/BUILD.tpl")),
        "_settings": attr.label(default = Label("//source/bazel:toolchains/host/settings.bzl.tpl")),
    },
    environ = ["BAZEL_LLVM", "PATH", "TEMP"],
)
