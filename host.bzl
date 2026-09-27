# Copyright (c) 2023-present Matt Kaes and contributors

"""Locate host executables without replacing the installed LLVM toolchain."""

def _host(ctx):
    windows = "windows" in ctx.os.name.lower()
    llvm = ctx.os.environ.get("BAZEL_LLVM")
    executables = {
        "CLANG": "clang-cl",
        "LINKER": "lld-link",
        "NM": "llvm-nm" if windows else "nm",
        "PYTHON": "python" if windows else "python3",
    }
    if windows:
        executables["ARCHIVER"] = "llvm-lib"
    values = {"HOST_SYSTEM": "windows" if windows else "linux"}
    for name, executable in executables.items():
        selected = ctx.path(llvm + "/bin/" + executable + ".exe") if windows and llvm and name != "PYTHON" else ctx.which(executable)
        if not selected:
            fail("Install " + executable + " on PATH or set BAZEL_LLVM to the LLVM installation")
        values[name] = str(selected).replace("\\", "/")
    resource = ctx.execute([values["CLANG"], "/clang:-print-resource-dir"])
    if resource.return_code:
        fail(resource.stderr)
    values["RESOURCE_INCLUDE"] = resource.stdout.strip().replace("\\", "/") + "/include"
    values["PATH"] = ctx.os.environ.get("PATH", "")
    values["TEMP"] = ctx.os.environ.get("TEMP", "/tmp")
    files = []
    if not windows:
        # LLD selects library mode before expanding response files. Keep /lib
        # in its direct arguments and use the linker selected above.
        linker = "'" + values["LINKER"].replace("'", "'\\''") + "'"
        ctx.file("archive.sh", "#!/bin/sh\nexec " + linker + " /lib \"$@\"\n", executable = True)
        values["ARCHIVER"] = str(ctx.path("archive.sh"))
        files.append("archive.sh")
    ctx.file("settings.bzl", "\n".join([key + " = " + repr(value) for key, value in values.items()]) + "\n")
    ctx.file("BUILD.bazel", 'exports_files(["settings.bzl"])\nfilegroup(name = "files", srcs = ' + repr(files) + ', visibility = ["//visibility:public"])')

host_tools = repository_rule(implementation = _host, environ = ["BAZEL_LLVM", "PATH", "TEMP"], local = True)
