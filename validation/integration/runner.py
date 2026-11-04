# Copyright (c) 2023-present Matt Kaes and contributors

"""Run integration programs directly, without a Bazel test executor."""

from concurrent.futures import ThreadPoolExecutor, as_completed
import json
from pathlib import Path
import subprocess
import sys
import time


def run(command):
    started = time.monotonic()
    if Path(command[0]).suffix == ".py":
        command = [sys.executable, "-I", "-B", "-X", "utf8", *command]

    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
    return result, time.monotonic() - started


if __name__ == "__main__":
    inventory = (
        sys.argv[1]
        if len(sys.argv) > 1
        else ".bin/bin/validation/integration/integration_commands.json"
    )

    commands = json.loads(Path(inventory).read_text(encoding="utf-8"))
    failed = []
    with ThreadPoolExecutor() as processes:
        pending = {
            processes.submit(run, command): name for name, command in commands.items()
        }

        for future in as_completed(pending):
            name = pending[future]
            result, elapsed = future.result()
            print(
                f"{name}: {'FAILED' if result.returncode else 'PASSED'} in {elapsed:.1f}s",
                flush=True,
            )

            if result.returncode:
                failed.append(name)
                print(result.stdout + result.stderr, flush=True)

    print(f"{len(commands) - len(failed)}/{len(commands)} integration programs passed.")
    sys.exit(bool(failed))
