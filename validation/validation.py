# Copyright (c) 2023-present Matt Kaes and contributors

"""Check the ordinary validation executables through their process boundary."""

import os
from pathlib import Path
import re
import subprocess
import sys

from python.runfiles import runfiles


def run(program, *arguments, status=0, color=False):
    environment = os.environ.copy()
    if color:
        environment.pop("NO_COLOR", None)
    else:
        environment["NO_COLOR"] = "1"
    result = subprocess.run(
        [program, *arguments], capture_output=True, text=True,
        env=environment, timeout=30,
    )
    assert result.returncode == status, result.stdout + result.stderr
    assert not result.stderr, result.stderr
    return result.stdout


def verify_tests(program, reporting, skipped, empty, source):
    output = run(program)
    assert "4 / 4 (100.00%)" in output, output
    for name in ["evaluates_each_operand_once", "compares_complete_byte_ranges",
                 "bounded_strings", "preserves_byte_element_type"]:
        assert re.search(r"\[ PASS\s+\] " + name + r"\s", output), output
    assert output.startswith("unit fixture constructed\n"), output
    finished = "unit fixture destroyed: init=1 setup=4 teardown=4 value=-1\n"
    assert output.endswith(finished), output
    silent = run(program, "silent")
    assert silent == "unit fixture constructed\n" + finished, silent

    locations = {}
    for number, line in enumerate(Path(source).read_text().splitlines(), 1):
        match = re.match(r"VALIDATION_TEST\(Reporting, (\w+)\)", line)
        if match:
            locations[match[1]] = f"validation/reporting.cpp:{number}: Reporting::{match[1]}"

    # Failure output comes from real EXPECT, ASSERT and SKIP calls. Only the
    # outside process may expect their nonzero exit status and inspect the
    # destructor output produced after the framework's main has returned.
    for arguments in [(), ("silent",)]:
        raw = run(reporting, *arguments, status=1, color=not arguments)
        output = re.sub(r"\x1b\[[0-9;]*m", "", raw)
        assert output.startswith("report fixture constructed\n"), output
        assert output.endswith("report fixture destroyed: setup=4 teardown=4\n"), output
        assert "continued after EXPECT" in output, output
        assert "unreachable after" not in output, output
        for value in ["false", "1.25", "-2.5", "-128", "-7",
                      "-9223372036854775808", "18446744073709551615",
                      "00 7F FF ", "aXc!", "a\0X", "<value>", "range"]:
            assert re.search(r"ACTUAL = " + value + r"\n", output), output
        assert output.count("ACTUAL = <value>\n") == 2, output
        failures = output.split("Failed tests:\n", 1)[1].split("Slow tests", 1)[0]
        assert locations["failure"] in failures, output
        assert locations["assertion"] in failures, output
        slow = output.split("Slow tests (>= 1000 ms):\n", 1)[1]
        assert locations["slow_pass"] in slow, output
        if arguments:
            assert "Pass Rate:" not in output and "Total Time:" not in output, output
        else:
            assert "1 / 3 (33.33%)" in output, output
            assert "ACTUAL = a\x1b[38;5;160mX\x1b[0mc\x1b[38;5;160m!\x1b[0m\n" in raw, raw
            for heading in ["Pass Rate:", "Total Time:"]:
                assert "\x1b[38;5;124m  " + heading + "\x1b[0m" in raw, raw

    for program in [skipped, empty]:
        output = run(program)
        assert "0 / 0 (n/a)" in output, output
        assert "Failed tests:" not in output, output
    assert run(empty, "silent") == ""


def verify_benchmarks(program):
    for arguments, expected in [
        ((), {"sum", "timed_sum"}),
        (("Su",), {"sum"}),
        (("aRithmetic",), {"sum", "timed_sum"}),
        (("Arithmetic-longer-than-any-name",), set()),
    ]:
        output = run(program, *arguments)
        assert output.startswith("benchmark fixture constructed\n"), output
        assert "Events" in output, output
        rows = re.findall(r"^  (sum|timed_sum)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)$", output, re.M)
        assert {row[0] for row in rows} == expected, output
        for _, fast, middle, slow, events in rows:
            assert 0 <= float(fast) <= float(middle) <= float(slow), output
            assert float(events) == 2, output
        lifecycle = re.search(
            r"benchmark fixture destroyed: init=(\d+) setup=(\d+) run=(\d+) "
            r"teardown=(\d+) errors=0 ready=0\n\Z", output,
        )
        assert lifecycle, output
        initialized, setups, runs, teardowns = map(int, lifecycle.groups())
        assert setups == runs == teardowns, output
        assert initialized == bool(expected), output
        assert runs > len(expected) if expected else runs == 0, output


if __name__ == "__main__":
    files = runfiles.Create()
    unit_tests, reporting, benchmark, skipped, empty, source = [
        files.Rlocation(path) for path in sys.argv[1:]
    ]
    verify_tests(unit_tests, reporting, skipped, empty, source)
    verify_benchmarks(benchmark)
    print("Validation executable checks passed.")
