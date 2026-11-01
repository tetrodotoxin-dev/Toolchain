# Copyright (c) 2023-present Matt Kaes and contributors

"""Execute Web validation through the host launcher and its runfiles."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from python.runfiles import runfiles


def run(program, *arguments, environment, directory, status=0):
    result = subprocess.run(
        [program, *arguments], cwd=directory, env=environment,
        shell=os.name == "nt", capture_output=True, text=True, timeout=60,
    )
    assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
    assert not result.stderr, result.stderr
    return result.stdout


if __name__ == "__main__":
    files = runfiles.Create()
    tests, benchmarks, node = [files.Rlocation(name) for name in sys.argv[1:]]
    environment = dict(os.environ, **files.EnvVars(), NO_COLOR="1")
    with tempfile.TemporaryDirectory(prefix="web tests with spaces ") as temporary:
        root = Path(temporary)
        output = run(tests, environment=environment, directory=root)
        assert "5 / 5 (100.00%)" in output, output
        output = run(tests, "silent", environment=environment, directory=root)
        assert "Testing Completed:" not in output, output
        assert output.endswith("test fixture destroyed: init=1 setup=5 teardown=5 value=-1\n"), output
        output = run(benchmarks, "Su", environment=environment, directory=root)
        assert "  sum " in output and "timed_sum" not in output, output
        assert "errors=0 ready=0" in output, output

        # A replacement program checks argument boundaries and failure status.
        # Windows uses the manifest; Linux uses a physical runfiles directory.
        program = root / "program with spaces.js"
        arguments = ["with spaces", "last"]
        program.write_text(
            "if (JSON.stringify(process.argv.slice(2)) !== "
            + json.dumps(json.dumps(arguments, separators=(",", ":")))
            + ") process.exit(18);\nprocess.exit(17);\n",
            encoding="utf-8", newline="\n",
        )
        environment["RUNFILES_DIR"] = str(root / "runfiles")
        if os.name == "nt":
            manifest = root / "custom manifest"
            manifest.write_text(
                f"{sys.argv[3]} {node}\n_main/tests_web_binary {program}\n",
                encoding="utf-8", newline="\n",
            )
            environment["RUNFILES_MANIFEST_FILE"] = str(manifest)
            # The launcher must resolve its pinned runtime without Node on PATH.
            environment["PATH"] = ""
        else:
            node_link = root / "runfiles" / sys.argv[3]
            node_link.parent.mkdir(parents=True)
            node_link.symlink_to(node)
            program_link = root / "runfiles/_main/tests_web_binary"
            program_link.parent.mkdir(parents=True)
            program_link.symlink_to(program)
        run(tests, *arguments, environment=environment, directory=root, status=17)
    print("Web tests, benchmark filtering, runfiles, arguments and exit status passed.")
