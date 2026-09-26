#!/usr/bin/env python3
"""Write COFF definitions for the objects owned by one shared library."""
import subprocess
import sys

symbols = {}
for line in subprocess.check_output(["nm", "--extern-only", "--defined-only", "--format=posix", *sys.argv[2:]], text=True).splitlines():
    fields = line.split()
    if len(fields) >= 2 and fields[1] in ("T", "D", "B", "R"):
        symbols[fields[0]] = " DATA" if fields[1] != "T" else ""
with open(sys.argv[1], "w") as output:
    output.write("EXPORTS\n")
    for name, suffix in sorted(symbols.items()):
        output.write('"' + name + '"' + suffix + "\n")
