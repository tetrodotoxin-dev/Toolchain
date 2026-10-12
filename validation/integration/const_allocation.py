# Copyright (c) 2023-present Matt Kaes and contributors

"""Prove constant allocation cannot become a runtime allocation escape."""

from pathlib import Path
import subprocess
import sys
import tempfile

from python.runfiles import runfiles


def compile_source(compiler, include, source):
    with tempfile.TemporaryDirectory(prefix="const-allocation-") as temporary:
        path = Path(temporary) / "probe.cpp"
        path.write_text(source)
        return subprocess.run(
            [
                compiler,
                "-std=c++2c",
                "-fsyntax-only",
                "-I",
                str(include),
                str(path),
            ],
            capture_output=True,
            text=True,
        )


if __name__ == "__main__":
    resolver = runfiles.Create()
    compiler = resolver.Rlocation(sys.argv[1])
    header = Path(resolver.Rlocation(sys.argv[2]))
    include = header.parents[2]

    valid = compile_source(
        compiler,
        include,
        '#include "toolchain/memory/const_allocation.hpp"\n'
        "using namespace Toolchain::Memory;\n"
        "static_assert([] {\n"
        "  ConstAllocation<S32> values(2);\n"
        "  values.get_data()[1] = 42;\n"
        "  return values.get_capacity() == 2 && values.get_data()[1] == 42;\n"
        "}());\n",
    )
    assert valid.returncode == 0, valid.stderr

    runtime = compile_source(
        compiler,
        include,
        '#include "toolchain/memory/const_allocation.hpp"\n'
        "using namespace Toolchain::Memory;\n"
        "auto allocate_at_runtime() -> void {\n"
        "  ConstAllocation<S32> values(2);\n"
        "}\n",
    )
    assert runtime.returncode != 0, runtime.stderr
    assert "constant expression" in runtime.stderr, runtime.stderr

    bypass = compile_source(
        compiler,
        include,
        '#include "toolchain/memory/lifetime.hpp"\n'
        "using namespace Toolchain::Memory;\n"
        "auto bypass_source_policy() -> S32* {\n"
        "  return Lifetime::allocate_object<S32>();\n"
        "}\n",
    )
    assert bypass.returncode != 0, bypass.stderr
    assert "no member named 'allocate_object'" in bypass.stderr, bypass.stderr
