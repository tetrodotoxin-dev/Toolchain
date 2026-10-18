# Copyright (c) 2023-present Matt Kaes and contributors

"""Verify that snapshots preserve one clean Git commit exactly."""

import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

from python.runfiles import runfiles


def run(command, root, status=0):
    environment = os.environ.copy()
    environment["BUILD_WORKSPACE_DIRECTORY"] = str(root)
    result = subprocess.run(
        command,
        cwd=root,
        env=environment,
        capture_output=True,
        text=True,
    )
    assert result.returncode == status, result.stdout + result.stderr
    return result


if __name__ == "__main__":
    resolver = runfiles.Create()
    program = resolver.Rlocation(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="toolchain-snapshot-test-") as temporary:
        root = Path(temporary)
        subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "validation@tetrodotoxin.dev"],
            cwd=root,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Toolchain Validation"],
            cwd=root,
            check=True,
        )
        (root / ".gitignore").write_text(".bin/\nignored.txt\n")
        (root / "source").mkdir()
        executable = root / "source/tool.sh"
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        (root / "README.md").write_text("snapshot fixture\n")
        (root / "ignored.txt").write_text("ignored\n")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        environment = os.environ.copy()
        environment.update({
            "GIT_AUTHOR_DATE": "2000-01-01T00:00:00+00:00",
            "GIT_COMMITTER_DATE": "2000-01-01T00:00:00+00:00",
        })
        subprocess.run(
            ["git", "commit", "--quiet", "-m", "snapshot fixture"],
            cwd=root,
            env=environment,
            check=True,
        )
        commit = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        first = run([program], root)
        archive = root / ".bin/release/tetro_toolchain-0.4.0-source.tar.gz"
        assert archive.exists(), first.stdout
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        assert archive.with_name(archive.name + ".sha256").read_text() == (
            digest + "  " + archive.name + "\n"
        )
        assert archive.with_name(archive.name + ".commit").read_text() == (
            commit + "\n"
        )
        with tarfile.open(archive, "r:gz") as snapshot:
            names = snapshot.getnames()
            assert names == [
                ".gitignore",
                "README.md",
                "source",
                "source/tool.sh",
            ], names
            assert snapshot.getmember("source/tool.sh").mode & 0o111
        run([program], root)
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == digest
        (root / "README.md").write_text("dirty fixture\n")
        failure = run([program], root, status=1)
        assert "snapshot requires a clean Git worktree" in failure.stderr
    print("Git snapshot checks passed.")
