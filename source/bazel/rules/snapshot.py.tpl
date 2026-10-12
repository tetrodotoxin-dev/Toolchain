# Copyright (c) 2023-present Matt Kaes and contributors

"""Create a reproducible source archive from a clean Git commit."""

import hashlib
import os
from pathlib import Path
import subprocess
import sys


PROJECT = __PROJECT__
VERSION = __VERSION__


def git(root, *arguments):
    return subprocess.run(
        ["git", *arguments],
        cwd=root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def main():
    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace:
        print("snapshot runs through `bazel run :snapshot`", file=sys.stderr)
        return 1
    root = Path(workspace).resolve()
    try:
        repository = Path(git(root, "rev-parse", "--show-toplevel")).resolve()
    except subprocess.CalledProcessError as error:
        print(error.stderr.strip(), file=sys.stderr)
        return 1
    if repository != root:
        print("snapshot must run from the repository root", file=sys.stderr)
        return 1
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    if status:
        print("snapshot requires a clean Git worktree:", file=sys.stderr)
        print(status, file=sys.stderr)
        return 1
    commit = git(root, "rev-parse", "HEAD")
    directory = root / ".bin/release"
    directory.mkdir(parents=True, exist_ok=True)
    name = PROJECT + "-" + VERSION + "-source.tar.gz"
    archive = directory / name
    temporary = directory / (name + ".tmp")
    temporary.unlink(missing_ok=True)
    try:
        subprocess.run(
            [
                "git",
                "archive",
                "--format=tar.gz",
                "--output=" + str(temporary),
                commit,
            ],
            cwd=root,
            check=True,
        )
        temporary.replace(archive)
    finally:
        temporary.unlink(missing_ok=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_name(archive.name + ".sha256")
    revision = archive.with_name(archive.name + ".commit")
    checksum.write_text(digest + "  " + archive.name + "\n")
    revision.write_text(commit + "\n")
    print("Snapshot: " + str(archive))
    print("Commit: " + commit)
    print("SHA-256: " + digest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
