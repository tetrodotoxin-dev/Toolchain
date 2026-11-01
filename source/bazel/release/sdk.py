# Copyright (c) 2023-present Matt Kaes and contributors

"""Format sources and run host tests before building release archives."""

import os
from pathlib import Path
import subprocess
import sys


def main():
    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    execroot = os.environ.get("BUILD_EXECROOT")
    if not workspace or not execroot or len(sys.argv) != 2:
        print("SDK releases run through `bazel run :sdk`", file=sys.stderr)
        return 1
    bazel = os.environ.get("BAZEL_REAL") or "bazel"
    command = [bazel, "--output_base=" + str(Path(execroot).parent.parent)]
    environment = {name: value for name, value in os.environ.items() if not name.startswith("RUNFILES_")}
    options = ["-c", "opt", "--strip=always", "--platforms=@bazel_tools//tools:host_platform"]
    for arguments in [
        ["run", "//:format"],
        ["run", "//:tests"],
        ["build", sys.argv[1]],
    ]:
        result = subprocess.run([*command, *arguments, *options], cwd=workspace, env=environment)
        if result.returncode:
            return result.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
