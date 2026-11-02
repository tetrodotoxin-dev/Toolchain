# Copyright (c) 2023-present Matt Kaes and contributors

"""Supply one LLVM distribution for the execution host and every target.

Bazel verifies and caches the pinned archive. BAZEL_LLVM is the explicit local
installation override used for compiler development. Target SDKs remain
separate inputs because the host chooses which tools run, while the target
chooses the headers and libraries they consume.
"""

def _host(ctx):
    """Publish host settings beside a view of the selected LLVM files.

    Args:
        ctx: Repository context supplying the host platform and environment.
    """
    system = ctx.os.name.lower()
    system = "windows" if "windows" in system else system
    # Distribution changes must refresh compiler-derived host settings.
    ctx.watch(Label("//source/bazel:toolchains/host/distribution.bzl"))
    ctx.symlink(ctx.path(ctx.attr._distribution).dirname.get_child("llvm"), "llvm")
    suffix = ".exe" if system == "windows" else ""
    executables = {
        "CXX": "clang++",
        "CLANG": "clang-cl",
        "CLANG_FORMAT": "clang-format",
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
        files.append(location)

        # LLVM aliases need their resolved executable in runfiles. Windows may
        # copy an alias instead, leaving the selected path as the actual file.
        if selected.realpath.basename != selected.basename:
            files.append("llvm/bin/" + selected.realpath.basename)
    resource = ctx.execute([values["CXX"], "-print-resource-dir"])
    if resource.return_code:
        fail(resource.stderr)

    values["RESOURCE_INCLUDE"] = resource.stdout.strip().replace("\\", "/") + "/include"
    python = ctx.path(Label("@host_python//:BUILD.bazel")).dirname.get_child("python" + suffix)
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
        "_distribution": attr.label(default = Label("@llvm_distribution//:BUILD.bazel")),
        "_build": attr.label(default = Label("//source/bazel:toolchains/host/tools.build")),
        "_settings": attr.label(default = Label("//source/bazel:toolchains/host/settings.bzl.tpl")),
    },
    environ = ["BAZEL_LLVM", "PATH", "TEMP"],
)
