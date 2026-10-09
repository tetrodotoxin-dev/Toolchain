# Copyright (c) 2023-present Matt Kaes and contributors

"""Exercise formatting and namespace validation through the public target."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

from python.runfiles import runfiles


def run(program, root, *arguments, status=0):
    environment = os.environ.copy()
    environment["BUILD_WORKSPACE_DIRECTORY"] = str(root)
    result = subprocess.run(
        [program, *arguments],
        capture_output=True,
        env=environment,
        text=True,
    )
    assert result.returncode == status, repr(arguments) + "\n" + result.stdout + result.stderr
    return result


if __name__ == "__main__":
    resolver = runfiles.Create()
    formatter = resolver.Rlocation(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="toolchain-format-") as temporary:
        root = Path(temporary)
        (root / "MODULE.bazel").write_text(
            'module(name = "example")\n'
            'sdks = use_extension("@tetro_toolchain//source/bazel:sdk.bzl", "dependencies")\n'
            'sdks.release(name = "runtime", project = "Runtime")\n'
            'sdks.release(name = "foundation", project = "Foundation")\n'
        )
        source = root / "source"
        source.mkdir()

        valid = source / "valid.cpp"
        valid.write_text(
            '#include "valid.hpp"\n'
            "using namespace Example::Module;\nint main(){return 0;}\n"
        )
        result = run(formatter, root, "source/valid.cpp")
        assert result.stdout == "Formatted 1 source files.\n", result.stdout
        assert valid.read_text() == (
            '#include "valid.hpp"\n'
            "using namespace Example::Module;\n"
            "int main() {\n"
            "  return 0;\n"
            "}\n"
        ), valid.read_text()
        result = run(formatter, root, "--check", "source/valid.cpp")
        assert result.stdout == "Checked 1 source files.\n", result.stdout

        includes = source / "includes.cpp"
        includes.write_text(
            '#include "zeta/value.hpp"\n\n'
            '#include "foundation/value.hpp"\n\n'
            "#include <vector>\n\n"
            '#include "includes.hpp"\n\n'
            '#include "runtime/value.hpp"\n\n'
            "#include <stdio.h>\n\n"
            '#include "toolchain/export.h"\n\n'
            '#include "alpha/value.hpp"\n'
        )
        run(formatter, root, "source/includes.cpp")
        assert includes.read_text() == (
            '#include "includes.hpp"\n\n'
            "#include <stdio.h>\n\n"
            "#include <vector>\n\n"
            '#include "toolchain/export.h"\n\n'
            '#include "runtime/value.hpp"\n\n'
            '#include "foundation/value.hpp"\n\n'
            '#include "alpha/value.hpp"\n'
            '#include "zeta/value.hpp"\n'
        )
        assert not (root / ".clang-format").exists()

        header = source / "valid.hpp"
        header.write_text("namespace Example::Module {\nclass Value {};\n}\n")
        run(formatter, root, "source/valid.hpp")

        owned = source / "example" / "module" / "folder"
        owned.mkdir(parents=True)
        owned_header = owned / "header.hpp"
        owned_header.write_text(
            "#pragma once\n"
            "namespace Example::Module::Folder {\nclass Header {};\n}\n"
        )
        run(formatter, root, "source/example/module/folder/header.hpp")

        paired = source / "example" / "module" / "paired"
        paired.with_suffix(".hpp").write_text(
            "#pragma once\nnamespace Example::Module {\nclass Paired {};\n}\n"
        )
        paired.with_suffix(".cpp").write_text(
            "#include <stddef.h>\n#include \"example/module/paired.hpp\"\n"
        )
        result = run(
            formatter,
            root,
            "--check",
            "source/example/module/paired.cpp",
            status=1,
        )
        assert "matching header" in result.stderr
        paired.with_suffix(".cpp").write_text(
            '#include "example/module/paired.hpp"\n#include <stddef.h>\n'
        )
        run(formatter, root, "source/example/module/paired.cpp")

        image = source / "example" / "image"
        image.mkdir()
        texture = image / "texture_2d.hpp"
        texture.write_text(
            "#pragma once\nnamespace Example::Image {\nclass Texture2D {};\n}\n"
        )
        run(formatter, root, "source/example/image/texture_2d.hpp")

        diagnostics = source / "example" / "core" / "diagnostics"
        diagnostics.mkdir(parents=True)
        source_location = diagnostics / "source.hpp"
        source_location.write_text(
            "#pragma once\n"
            "namespace std {\n"
            "class source_location {\n"
            " public:\n"
            "  struct __impl {};\n"
            "};\n"
            "}\n"
            "namespace Example::Core::Diagnostics {\n"
            "class Source {\n"
            " public:\n"
            "  static auto current(\n"
            "      const std::source_location::__impl* value = "
            "__builtin_source_location()) -> Source;\n"
            "};\n"
            "}\n"
        )
        run(formatter, root, "source/example/core/diagnostics/source.hpp")

        prelude = source / "example" / "core"
        prelude.mkdir(exist_ok=True)
        (prelude / "example.h").write_text("typedef unsigned char U8;\n")
        (prelude / "example.hpp").write_text(
            "#pragma once\n"
            '#include "example/core/example.h"\n'
            "namespace Example::Core {\n"
            "enum class Placement : U8 { Construct };\n"
            "}\n"
        )
        run(formatter, root, "source/example/core/example.hpp")

        invalid_headers = {
            "wrong_namespace.hpp": (
                "#pragma once\n"
                "namespace Example::Other {\nclass WrongNamespace {};\n}\n",
                "public header namespaces match",
            ),
            "wrong_object.hpp": (
                "#pragma once\n"
                "namespace Example::Module::Folder {\nclass Other {};\n}\n",
                "primary object",
            ),
            "outside_object.hpp": (
                "#pragma once\n"
                "class OutsideObject {};\n"
                "namespace Example::Module::Folder {}\n",
                "primary object",
            ),
            "platform.hpp": (
                "#pragma once\n#ifdef PERI_LINUX\n#endif\n"
                "namespace Example::Module::Folder {\nclass Platform {};\n}\n",
                "target independent contract",
            ),
            "platform_include.hpp": (
                "#pragma once\n#include <windows.h>\n"
                "namespace Example::Module::Folder {\n"
                "class PlatformInclude {};\n}\n",
                "target independent SDK contracts",
            ),
            "unguarded.hpp": (
                "namespace Example::Module::Folder {\nclass Unguarded {};\n}\n",
                "#pragma once",
            ),
        }
        for name, (content, diagnostic) in invalid_headers.items():
            path = owned / name
            path.write_text(content)
            result = run(
                formatter,
                root,
                "source/example/module/folder/" + name,
                status=1,
            )
            assert diagnostic in result.stderr
            path.unlink()

        masked = source / "masked.cpp"
        masked.write_text(
            'const char* text = "using namespace Example::Module::Detail;";\n'
            'const char* raw = R"(namespace Example::Module {})";\n'
            "// namespace Example::Module {}\n"
            "/* namespace Example::Module::Detail appears in prose. */\n"
        )
        run(formatter, root, "source/masked.cpp")

        paragraph = source / "paragraph.cpp"
        paragraph.write_text(
            "auto paragraph() -> int {\n"
            "  int value = 0;\n"
            "  value++;\n\n"
            "  int selected = value;\n"
            "  selected++;\n"
            "  if (selected) {\n"
            "    selected++;\n"
            "  }\n\n"
            "  return selected;\n"
            "}\n"
        )
        run(formatter, root, "source/paragraph.cpp")

        indexed_statements = source / "indexed_statements.cpp"
        indexed_statements.write_text(
            "auto update(int* values) -> void {\n"
            "  values[0]++;\n"
            "  values[1]++;\n"
            "}\n"
        )
        run(formatter, root, "source/indexed_statements.cpp")
        run(formatter, root, "--check", "source/indexed_statements.cpp")

        preprocessor = source / "preprocessor.cpp"
        preprocessor.write_text(
            "#ifdef PLATFORM\n"
            "#include <stddef.h>\n"
            "#endif\n\n"
            "#define FIRST 1\n"
            "#define SECOND 2\n\n"
            "auto select() -> int {\n\n"
            "#if FIRST\n\n"
            "  return FIRST;\n\n"
            "#else\n\n"
            "  return SECOND;\n\n"
            "#endif\n"
            "}\n"
        )
        run(formatter, root, "source/preprocessor.cpp")

        invalid = {
            "root.cpp": "using namespace Example;\n",
            "deep.cpp": "using namespace Example::Module::Detail;\n",
            "block.cpp": "namespace Example::Module {\nint value;\n}\n",
            "anonymous.cpp": "namespace {\nint value;\n}\n",
            "alias.cpp": "namespace Alias = Example::Module;\n",
            "import.hpp": "using namespace Example::Module;\n",
        }
        for name, content in invalid.items():
            path = source / name
            path.write_text(content)
            result = run(formatter, root, "source/" + name, status=1)
            assert "SDK::Module" in result.stderr or "namespace ownership" in result.stderr
            path.unlink()

        invalid_comments = {
            "hyphen.cpp": "// Author-owned language.\nint value;\n",
            "semicolon.cpp": "// One clause; another clause.\nint value;\n",
            "em_dash.cpp": "// One clause — another clause.\nint value;\n",
            "en_dash.cpp": "// One clause – another clause.\nint value;\n",
            "filler.cpp": "// This simply returns the value.\nint value;\n",
            "obvious.cpp": "// This obviously preserves the value.\nint value;\n",
            "seamless.cpp": "// This seamlessly preserves the value.\nint value;\n",
            "leverage.cpp": "// Leverage the value here.\nint value;\n",
            "utilize.cpp": "// Utilize the value here.\nint value;\n",
        }
        for name, content in invalid_comments.items():
            path = source / name
            path.write_text(content)
            result = run(formatter, root, "source/" + name, status=1)
            assert "comments" in result.stderr or "filler phrase" in result.stderr
            path.unlink()

        accepted_comment = source / "accepted_comment.cpp"
        accepted_comment.write_text(
            "// Copyright (c) 2023-present Matt Kaes and contributors\n"
            "// A missing value has no endpoint and cannot provide storage without a\n"
            "// candidate. Compare bytes rather than addresses instead of relying on\n"
            "// pointer identity because an address is not a value identity.\n"
            "int value;\n"
        )
        run(formatter, root, "source/accepted_comment.cpp")
        run(formatter, root, "--check", "source/accepted_comment.cpp")

        invalid_declarations = {
            "const_cast.cpp": (
                "auto expose(const int* value) -> int* {\n"
                "  return const_cast<int*>(value);\n"
                "}\n"
            ),
            "mutable.hpp": "struct Value { mutable int state; };\n",
            "class.hpp": "class Forward;\n",
            "enum.hpp": "enum class Forward : unsigned;\n",
        }
        for name, content in invalid_declarations.items():
            path = source / name
            path.write_text(content)
            result = run(formatter, root, "source/" + name, status=1)
            assert (
                "const qualification" in result.stderr
                or "owner contract" in result.stderr
                or "complete owner" in result.stderr
            )
            path.unlink()

        invalid_returns = {
            "leading_return.cpp": "int value() { return 1; }\n",
            "deduced_return.cpp": "auto value() { return 1; }\n",
            "call_operator.cpp": (
                "struct Callable {\n"
                "  auto operator()() { return 1; }\n"
                "};\n"
            ),
            "index_operator.cpp": (
                "struct Indexed {\n"
                "  auto operator[](int) { return 1; }\n"
                "};\n"
            ),
            "comparison_operator.cpp": (
                "struct Comparable {\n"
                "  auto operator==(const Comparable&) const { return true; }\n"
                "};\n"
            ),
            "digit_separator.cpp": (
                "auto first() -> int { return 1'000; }\n"
                "int second() { return 2; }\n"
            ),
        }
        for name, content in invalid_returns.items():
            path = source / name
            path.write_text(content)
            result = run(formatter, root, "source/" + name, status=1)
            assert "trailing return types" in result.stderr
            path.unlink()

        constructors = source / "constructors.hpp"
        constructors.write_text(
            "class Constructors {\n"
            " public:\n"
            "  Constructors() = default;\n"
            "  ~Constructors() = default;\n"
            "  explicit operator bool() const { return true; }\n"
            "};\n"
        )
        run(formatter, root, "source/constructors.hpp")

        deleted_operation = source / "deleted_operation.hpp"
        deleted_operation.write_text(
            "class DeletedOperation {\n"
            " public:\n"
            "  DeletedOperation(const DeletedOperation&) = delete;\n"
            "};\n"
        )
        run(formatter, root, "source/deleted_operation.hpp")

        raw_allocation = source / "raw_allocation.cpp"
        raw_allocation.write_text(
            "auto allocate() -> int* {\n"
            "  return new int;\n"
            "}\n"
            "auto release(int* value) -> void {\n"
            "  delete value;\n"
            "}\n"
        )
        result = run(
            formatter,
            root,
            "source/raw_allocation.cpp",
            status=1,
        )
        assert "exact path registration" in result.stderr
        (root / "toolchain.json").write_text(
            '{\n  "raw_allocation_files": [\n'
            '    "source/raw_allocation.cpp"\n'
            "  ]\n}\n"
        )
        run(formatter, root, "source/raw_allocation.cpp")
        run(formatter, root, "--check", "source/raw_allocation.cpp")

        unregistered_allocation = source / "unregistered_allocation.cpp"
        unregistered_allocation.write_text(
            "auto release(void* value) -> void {\n"
            "  free(value);\n"
            "}\n"
        )
        result = run(
            formatter,
            root,
            "source/unregistered_allocation.cpp",
            status=1,
        )
        assert "exact path registration" in result.stderr
        unregistered_allocation.unlink()

        allocation_macro = source / "allocation_macro.cpp"
        allocation_macro.write_text("#define ALLOCATE() new int\n")
        result = run(
            formatter,
            root,
            "source/allocation_macro.cpp",
            status=1,
        )
        assert "exact path registration" in result.stderr
        allocation_macro.unlink()

        repairable_paragraphs = {
            "statement_declaration.cpp": (
                "auto value() -> int {\n"
                "  int value = 0;\n"
                "  value++;\n"
                "  int selected = value;\n"
                "  return selected;\n"
                "}\n"
            ),
            "block_statement.cpp": (
                "auto value(bool ready) -> int {\n"
                "  if (ready) {\n"
                "    return 1;\n"
                "  }\n"
                "  return 0;\n"
                "}\n"
            ),
            "block_block.cpp": (
                "auto value(bool first, bool second) -> int {\n"
                "  if (first) {\n"
                "    return 1;\n"
                "  }\n"
                "  if (second) {\n"
                "    return 2;\n"
                "  }\n"
                "  return 0;\n"
                "}\n"
            ),
        }
        for name, content in repairable_paragraphs.items():
            path = source / name
            path.write_text(content)
            result = run(formatter, root, "--check", "source/" + name, status=1)
            assert "lexical paragraphs" in result.stderr
            run(formatter, root, "source/" + name)
            run(formatter, root, "--check", "source/" + name)
            assert "\n\n" in path.read_text()
            path.unlink()

        independent_blocks = source / "independent_blocks.cpp"
        independent_blocks.write_text(
            "auto select(bool first, bool second) -> int {\n"
            "  if (first) {\n"
            "    second = false;\n"
            "  }\n"
            "  for (int index = 0; index < 1; ++index) {\n"
            "    second = true;\n"
            "  }\n"
            "  while (second) {\n"
            "    second = false;\n"
            "  }\n"
            "  switch (first) {\n"
            "    case true:\n"
            "      second = true;\n"
            "      break;\n"
            "    case false:\n"
            "      break;\n"
            "  }\n"
            "  try {\n"
            "    second = true;\n"
            "  } catch (...) {\n"
            "    second = false;\n"
            "  }\n"
            "  do {\n"
            "    second = false;\n"
            "  } while (second);\n"
            "  return second;\n"
            "}\n"
        )
        result = run(
            formatter,
            root,
            "--check",
            "source/independent_blocks.cpp",
            status=1,
        )
        assert "lexical paragraphs" in result.stderr
        run(formatter, root, "source/independent_blocks.cpp")
        formatted_blocks = independent_blocks.read_text()
        assert "  }\n\n  for" in formatted_blocks
        assert "  }\n\n  while" in formatted_blocks
        assert "  }\n\n  switch" in formatted_blocks
        assert "  }\n\n  try" in formatted_blocks
        assert "  }\n\n  do" in formatted_blocks
        assert "  } while (second);\n\n  return" in formatted_blocks
        run(formatter, root, "source/independent_blocks.cpp")
        assert independent_blocks.read_text() == formatted_blocks
        run(formatter, root, "--check", "source/independent_blocks.cpp")

        attached_else = source / "attached_else.cpp"
        attached_else.write_text(
            "auto select(bool first, bool second) -> int {\n"
            "  if (first) {\n"
            "    return 1;\n"
            "  } else if (second) {\n"
            "    return 2;\n"
            "  } else {\n"
            "    return 3;\n"
            "  }\n"
            "}\n"
        )
        run(formatter, root, "source/attached_else.cpp")
        formatted_else = attached_else.read_text()
        assert "  } else if" in formatted_else
        assert "  } else {" in formatted_else
        run(formatter, root, "--check", "source/attached_else.cpp")

        repairable_preprocessor = {
            "conditional.cpp": (
                "auto select() -> int {\n"
                "#if FIRST\n"
                "  return FIRST;\n"
                "#else\n"
                "  return 0;\n"
                "#endif\n"
                "}\n"
            ),
            "definition.cpp": "int value;\n#define VALUE 1\nint selected;\n",
        }
        for name, content in repairable_preprocessor.items():
            path = source / name
            path.write_text(content)
            result = run(formatter, root, "--check", "source/" + name, status=1)
            assert "conditional code" in result.stderr or "definition groups" in result.stderr
            run(formatter, root, "source/" + name)
            run(formatter, root, "--check", "source/" + name)
            path.unlink()

        run(formatter, root, "--all")
        run(formatter, root, "--check")
        assert not (root / ".clang-format").exists()
        result = run(formatter, root, status=2)
        assert "pass exact source files, --all, or --check" in result.stderr
        result = run(formatter, root, "../outside.cpp", status=2)
        assert "Source path leaves the workspace" in result.stderr
        result = run(formatter, root, "source", status=2)
        assert "Expected one C or C++ source file" in result.stderr
