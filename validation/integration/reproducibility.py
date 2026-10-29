# Copyright (c) 2023-present Matt Kaes and contributors

"""Rebuild source libraries and complete SDKs in independent workspaces."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

from python.runfiles import runfiles


HEADER = '''#pragma once
#include "toolchain/export.h"
C_LINKAGE EXPORTED(REPRO) const char* repro_file(void);
C_LINKAGE EXPORTED(REPRO) const char* repro_time(void);
C_LINKAGE EXPORTED(REPRO) const char* repro_location(void);
'''
C_SOURCE = '''#include "repro/api/library.h"
const char* repro_file(void) { return __FILE__; }
const char* repro_time(void) { return __DATE__ " " __TIME__ " " __TIMESTAMP__; }
'''
CPP_SOURCE = '''#include "repro/api/library.h"
#include "toolchain/compile/source_location.hpp"
const char* repro_location(void) {
  return Toolchain::Compile::SourceLocation::current().get_file();
}
'''
SOURCE_BUILD = '''load("@tetro_toolchain//:defs.bzl", "library")
package(default_visibility = ["//visibility:public"])
library(
    name = "static",
    module = "repro",
    srcs = ["library.c", "library.cpp"],
    hdrs = ["repro/api/library.h"],
    includes = ["."],
    components = {"api": []},
)
library(
    name = "shared",
    module = "repro",
    linkage = "shared",
    srcs = ["library.c", "library.cpp"],
    hdrs = ["repro/api/library.h"],
    includes = ["."],
)
'''
ROOT_BUILD = '''load("@tetro_toolchain//:defs.bzl", "package")
package(module = "repro", components = {"api": []},
        static = "//source:static", shared = "//source:shared")
'''


def verify_binary(name, content, forbidden):
    for path in forbidden:
        for spelling in {str(path), str(path).replace("\\", "/"), str(path).replace("/", "\\")}:
            for encoding in ("utf-8", "utf-16-le"):
                assert spelling.encode(encoding).lower() not in content.lower(), (
                    f"Build path {spelling} leaked into {name}"
                )
    assert not re.search(rb"[A-Za-z]:[\\/][ -~]{3,}", content), f"Absolute Windows path in {name}"
    if content.startswith(b"MZ"):
        offset = struct.unpack_from("<I", content, 0x3C)[0]
        assert struct.unpack_from("<I", content, offset + 8)[0] == 0, f"PE timestamp in {name}"
    if name.endswith(".obj"):
        offset = 8 if content.startswith(b"\0\0\xff\xff") else 4
        assert struct.unpack_from("<I", content, offset)[0] == 0, f"COFF timestamp in {name}"
    if content.startswith(b"!<arch>\n"):
        offset = 8
        while offset < len(content):
            header = content[offset:offset + 60]
            assert header[16:28].strip() in (b"", b"0"), f"Archive timestamp in {name}"
            size = int(header[48:58])
            offset += 60 + size + size % 2


def inventory(output, forbidden):
    result = {}
    debug_formats = set()
    binary_suffixes = {".o", ".obj", ".a", ".lib", ".dll", ".so", ".pdb", ".dwo"}
    for path in output.rglob("*"):
        if not path.is_file():
            continue
        name = path.relative_to(output).as_posix()
        if "/bin/source/" in name and path.suffix in binary_suffixes:
            content = path.read_bytes()
            if "-dbg/" in name:
                if path.suffix == ".obj":
                    assert b".debug$S" in content and b".debug$T" in content, name
                    debug_formats.add("CodeView")
                elif path.suffix == ".o":
                    assert b".debug_info" in content and b".debug_line" in content, name
                    debug_formats.add("DWARF")
                elif path.suffix == ".pdb":
                    assert b"library.c" in content and b"repro_location" in content, name
                    debug_formats.add("PDB")
                continue
            verify_binary(name, content, forbidden)
            result[name] = hashlib.sha256(content).hexdigest()
        elif path.name.startswith("repro-1.0.0-") and path.suffix in (".zip", ".txt"):
            content = path.read_bytes()
            if path.suffix == ".zip":
                with zipfile.ZipFile(path) as archive:
                    for info in archive.infolist():
                        assert info.date_time == (1980, 1, 1, 0, 0, 0), info
                        assert info.create_system == 3 and info.external_attr >> 16 == 0o100644, info
                        verify_binary(name + ":" + info.filename, archive.read(info), forbidden)
            result[name] = hashlib.sha256(content).hexdigest()
    assert sum(name.endswith(".zip") for name in result) == 7, result
    assert debug_formats == {"CodeView", "DWARF", "PDB"}, debug_formats
    return result


def build(bazel, archive, root, number):
    workspace = root / "source"
    workspace.mkdir(parents=True)
    version = archive.name.removeprefix("tetro_toolchain-").removesuffix("-source.tar.gz")
    module = f'''module(name = "repro", version = "1.0.0")
bazel_dep(name = "tetro_toolchain", version = "{version}")
archive_override(module_name = "tetro_toolchain", urls = [{json.dumps(archive.as_uri())}],
                 sha256 = "{hashlib.sha256(archive.read_bytes()).hexdigest()}")
'''
    for name, content in {
        "MODULE.bazel": module,
        "BUILD": ROOT_BUILD,
        "LICENSE": "Reproducibility fixture\n",
        ".bazelrc": "build --compilation_mode=dbg\n",
        "source/BUILD": SOURCE_BUILD,
        "source/repro/api/library.h": HEADER,
        "source/library.c": C_SOURCE,
        "source/library.cpp": CPP_SOURCE,
    }.items():
        path = workspace / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")
        os.utime(path, (1_000_000_000 + number * 100_000, 1_000_000_000 + number * 100_000))
    environment = os.environ.copy()
    environment.pop("BUILD_WORKSPACE_DIRECTORY", None)
    environment.pop("BUILD_WORKING_DIRECTORY", None)
    environment["PYTHONHASHSEED"] = str(number)
    base = root / "output"
    command = [bazel, "--batch", "--nosystem_rc", "--nohome_rc", "--output_base=" + str(base)]
    for targets in [
        ["//:sdk"],
        ["//source:static", "//source:shared_shared", "--platforms=@tetro_toolchain//:windows_x64"],
        ["//source:static", "//source:shared_shared", "--platforms=@tetro_toolchain//:linux_x86_64"],
    ]:
        subprocess.run(command + ["build", *targets], cwd=workspace, env=environment, check=True)
    forbidden = [root, archive.parent]
    home = environment.get("USERPROFILE") or environment.get("HOME")
    if home:
        forbidden.append(Path(home))
    return inventory(base / "execroot/_main/bazel-out", forbidden)


if __name__ == "__main__":
    resolver = runfiles.Create()
    archive = Path(resolver.Rlocation(sys.argv[1])).resolve()
    bazel = shutil.which("bazel")
    assert bazel, "The reproducibility integration check requires Bazel on PATH"
    with tempfile.TemporaryDirectory(prefix="repro-") as temporary:
        root = Path(temporary)
        first = build(bazel, archive, root / "first", 1)
        second = build(bazel, archive, root / "different-directory", 2)
        assert first.keys() == second.keys(), (first.keys() - second.keys(), second.keys() - first.keys())
        differences = [name for name in first if first[name] != second[name]]
        assert not differences, "Non-reproducible artifacts:\n" + "\n".join(differences)
        print(f"Matched {len(first)} release objects, libraries and SDK outputs across independent builds; debug information retained.")
