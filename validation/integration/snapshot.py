# Copyright (c) 2023-present Matt Kaes and contributors

"""Verify that snapshots preserve one clean Git commit exactly."""

from contextlib import redirect_stderr, redirect_stdout
import hashlib
import io
import os
from pathlib import Path
import runpy
import subprocess
import tarfile
import tempfile

def run(snapshot, root, version, status=0):
    output = io.StringIO()
    with redirect_stdout(output), redirect_stderr(output):
        result = snapshot(root, "tetro_toolchain", version)
    assert result == status, output.getvalue()
    return output.getvalue()


if __name__ == "__main__":
    snapshot = runpy.run_path("source/bazel/release/sdk.py")["snapshot"]
    version = "1.0.0"
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
        subprocess.run(
            ["git", "update-index", "--chmod=+x", "source/tool.sh"],
            cwd=root,
            check=True,
        )
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
        first = run(snapshot, root, version)
        archive = root / f".bin/release/tetro_toolchain-{version}-source.tar.gz"
        assert archive.exists(), first
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        assert archive.with_name(archive.name + ".sha256").read_text() == (
            digest + "  " + archive.name + "\n"
        )
        assert archive.with_name(archive.name + ".commit").read_text() == (
            commit + "\n"
        )
        with tarfile.open(archive, "r:gz") as contents:
            names = contents.getnames()
            assert names == [
                ".gitignore",
                "README.md",
                "source",
                "source/tool.sh",
            ], names
            assert contents.getmember("source/tool.sh").mode & 0o111
        run(snapshot, root, version)
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == digest
        (root / "README.md").write_text("dirty fixture\n")
        failure = run(snapshot, root, version, status=1)
        assert "snapshot requires a clean Git worktree" in failure
    print("Git snapshot checks passed.")
