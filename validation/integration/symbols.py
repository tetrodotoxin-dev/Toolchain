# Copyright (c) 2023-present Matt Kaes and contributors

"""Verify that shared-library construction embeds its private archive."""

import subprocess
import sys

from python.runfiles import runfiles


if __name__ == "__main__":
    files = runfiles.Create()
    nm, consumer, shared = [files.Rlocation(path) for path in sys.argv[1:]]
    subprocess.run([consumer], check=True)
    shared_symbols = subprocess.check_output([nm, shared], text=True)
    consumer_symbols = subprocess.check_output([nm, consumer], text=True)
    assert "toolchain_private_entry" in shared_symbols, shared_symbols
    assert "toolchain_private_entry" not in consumer_symbols, consumer_symbols
