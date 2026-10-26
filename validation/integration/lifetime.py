# Copyright (c) 2023-present Matt Kaes and contributors

"""Exercise placement construction with and without a host standard library."""

from pathlib import Path
import subprocess
import sys
import tempfile

from python.runfiles import runfiles


PROBE = r'''
struct Value {
  int value;
  constexpr explicit Value(int value) : value(value) {}
  Value(const Value&) = delete;
  Value(Value&&) = delete;
};

union Storage {
  Value value;
  constexpr Storage() {}
  constexpr ~Storage() {}
};

constexpr auto construct(int expected) -> bool {
  Storage storage;
  int calls = 0;
  auto& value = Toolchain::Memory::Lifetime::construct<Value>(
      &storage.value, [&] { ++calls; return Value(expected); });
  const bool correct = value.value == expected && calls == 1;
  value.~Value();
  return correct;
}

static_assert(construct(42));
int main(int argc, char** argv) { return construct(argc) ? 0 : 1; }
'''


if __name__ == "__main__":
    resolver = runfiles.Create()
    compiler = resolver.Rlocation(sys.argv[1])
    include = Path(resolver.Rlocation(sys.argv[2])).parents[2]
    with tempfile.TemporaryDirectory(prefix="placement-lifetime-") as temporary:
        root = Path(temporary)
        foreign = root / "foreign.hpp"
        foreign.write_text("#include <atomic>\n#include <new>\n")
        for name, headers in [
            ("standalone", '#include "toolchain/memory/lifetime.hpp"\n'),
            (
                "foreign_first",
                '#include "foreign.hpp"\n'
                '#include "toolchain/memory/lifetime.hpp"\n',
            ),
            (
                "foreign_after",
                '#include "toolchain/memory/lifetime.hpp"\n'
                '#include "foreign.hpp"\n',
            ),
        ]:
            source = root / (name + ".cpp")
            output = root / name
            source.write_text(headers + PROBE)
            for optimization in ["-O0", "-O2"]:
                subprocess.run([
                    compiler, "-std=c++26", optimization,
                    "-I", str(root), "-I", str(include), str(source),
                    "-o", str(output),
                ], check=True)
                subprocess.run([str(output)], check=True)

        # The standalone path stays independent of the standard C++ headers.
        source = root / "standalone.cpp"
        dependencies = subprocess.check_output([
            compiler, "-std=c++26", "-I", str(root), "-I", str(include),
            "-M", str(source),
        ], text=True)
        assert "/new" not in dependencies, dependencies
