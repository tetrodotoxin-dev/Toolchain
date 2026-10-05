# Copyright (c) 2023-present Matt Kaes and contributors

"""Keep SDK filesystem assumptions inside their published repository view."""

import json
import os
from pathlib import Path
import shutil
import sys


def linux(root):
    # Debian's absolute links describe the target filesystem. Point them into
    # this sysroot so neither the linker nor Bazel can follow them into the host.
    for path in root.rglob("*"):
        if path.is_symlink():
            target = os.readlink(path)
            if target.startswith("/"):
                destination = Path(target)
                if not destination.is_relative_to(root):
                    destination = root / target.lstrip("/")
                path.unlink()
                path.symlink_to(os.path.relpath(destination, path.parent))

    # The sysroot supplies headers, ABI libraries and startup objects. Locale
    # conversion, documentation and package configuration belong to the
    # deployed system that runs the completed binary.
    for relative in (
        "etc",
        "usr/lib/x86_64-linux-gnu/gconv",
        "usr/share",
    ):
        path = root / relative
        if path.exists():
            shutil.rmtree(path)

    # Dynamic Linux links still consume libgcc builtins, glibc's nonshared
    # support and the compatibility archives retained after glibc unified its
    # historical component libraries. This set states that complete contract.
    archives = {
        "usr/lib/x86_64-linux-gnu/libanl.a",
        "usr/lib/x86_64-linux-gnu/libc_nonshared.a",
        "usr/lib/x86_64-linux-gnu/libdl.a",
        "usr/lib/x86_64-linux-gnu/libpthread.a",
        "usr/lib/x86_64-linux-gnu/librt.a",
        "usr/lib/x86_64-linux-gnu/libutil.a",
    }
    archives.update(
        path.relative_to(root).as_posix()
        for path in root.glob("usr/lib/gcc/*/*/libgcc.a")
    )
    for path in root.rglob("*.a"):
        if path.relative_to(root).as_posix() not in archives:
            path.unlink()

    for path in root.glob("usr/lib/gcc/*/*/include/sanitizer"):
        shutil.rmtree(path)

    # Every published path resolves within the retained target filesystem.
    for path in root.rglob("*"):
        if path.is_symlink() and not path.exists():
            path.unlink()


def windows(root, virtual_root):
    # Keep conventional lowercase library names in the extracted SDK.
    for path in (root / "lib").rglob("*"):
        if path.is_file() and path.suffix.lower() == ".lib" and path.name != path.name.lower():
            path.rename(path.with_name(path.name.lower()))

    # Windows SDK headers use mixed spellings even within their own includes.
    # A case insensitive compiler view preserves those names on Linux without
    # duplicating files or changing the vendor headers.
    def directory(path, name):
        entries = []
        for child in sorted(path.iterdir()):
            if child.is_dir():
                entries.append(directory(child, child.name))
            else:
                # LLD checks the physical library path after VFS resolution.
                # Headers keep virtual names so later includes use this view.
                entries.append({"type": "file", "name": child.name,
                                "use-external-name": child.is_relative_to(root / "lib"),
                                "external-contents": child.resolve().as_posix()})
        return {"type": "directory", "name": name, "contents": entries}

    overlay = {"version": 0, "case-sensitive": False, "use-external-names": False,
               "roots": [directory(root / name, virtual_root + "/" + name)
                         for name in ("include", "lib")]}
    (root / "case.yaml").write_text(json.dumps(overlay))


if __name__ == "__main__":
    root = Path.cwd()
    if sys.argv[1] == "linux":
        linux(root)
    elif sys.argv[1] == "windows":
        windows(root, sys.argv[2])
    else:
        raise ValueError("Unknown SDK filesystem: " + sys.argv[1])
