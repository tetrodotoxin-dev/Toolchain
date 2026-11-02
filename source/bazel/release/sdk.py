# Copyright (c) 2023-present Matt Kaes and contributors

"""Format, test and package a release, then archive its clean Git commit."""

import hashlib
import os
from pathlib import Path
import subprocess
import sys


def git(root, *arguments):
    return subprocess.run(
        ["git", *arguments], cwd=root, capture_output=True, text=True, check=True,
    ).stdout.strip()


def snapshot(root, project, version):
    try:
        repository = Path(git(root, "rev-parse", "--show-toplevel")).resolve()
    except subprocess.CalledProcessError as error:
        print(error.stderr.strip(), file=sys.stderr)
        return 1
    if repository != root:
        print("SDK releases must run from the repository root", file=sys.stderr)
        return 1
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    if status:
        print("snapshot requires a clean Git worktree:", file=sys.stderr)
        print(status, file=sys.stderr)
        return 1
    commit = git(root, "rev-parse", "HEAD")
    directory = root / ".bin/release"
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / (project + "-" + version + "-source.tar.gz")
    temporary = archive.with_name(archive.name + ".tmp")
    try:
        subprocess.run(
            ["git", "archive", "--format=tar.gz", "--output=" + str(temporary), commit],
            cwd=root, check=True,
        )
        temporary.replace(archive)
    finally:
        temporary.unlink(missing_ok=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_name(archive.name + ".sha256").write_text(digest + "  " + archive.name + "\n")
    archive.with_name(archive.name + ".commit").write_text(commit + "\n")
    print("Snapshot: " + str(archive))
    print("Commit: " + commit)
    print("SHA-256: " + digest)
    return 0


def main():
    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    execroot = os.environ.get("BUILD_EXECROOT")
    if not workspace or not execroot or len(sys.argv) not in (4, 5):
        print("SDK releases run through `bazel run :sdk`", file=sys.stderr)
        return 1
    bazel = os.environ.get("BAZEL_REAL") or "bazel"
    command = [bazel, "--output_base=" + str(Path(execroot).parent.parent)]
    environment = {name: value for name, value in os.environ.items() if not name.startswith("RUNFILES_")}
    result = subprocess.run([str(Path(execroot) / sys.argv[3])], cwd=workspace, env=environment)
    if result.returncode:
        return result.returncode
    options = ["-c", "opt", "--strip=always", "--platforms=@bazel_tools//tools:host_platform"]
    stages = [
        ["run", "//:tests"],
    ]
    if len(sys.argv) == 5:
        stages.append(["build", sys.argv[4]])
    for arguments in stages:
        result = subprocess.run([*command, *arguments, *options], cwd=workspace, env=environment)
        if result.returncode:
            return result.returncode
    return snapshot(Path(workspace).resolve(), sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    sys.exit(main())
