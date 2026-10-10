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
        result = run(
            formatter,
            root,
            "--check",
            "source/valid.cpp",
            status=1,
        )
        assert "noncanonical numeric type 'int'" in result.stderr
        result = run(formatter, root, "source/valid.cpp")
        assert result.stdout == "Formatted 1 source files.\n", result.stdout
        assert valid.read_text() == (
            '#include "valid.hpp"\n'
            "using namespace Example::Module;\n"
            "S32 main() {\n"
            "  return 0;\n"
            "}\n"
        ), valid.read_text()
        result = run(formatter, root, "--check", "source/valid.cpp")
        assert result.stdout == "Checked 1 source files.\n", result.stdout

        includes = source / "includes.cpp"
        includes.write_text(
            '#include "zeta/value.hpp"\n\n'
            '#include "foundation/value.hpp"\n\n'
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
            '#include "toolchain/export.h"\n\n'
            '#include "runtime/value.hpp"\n\n'
            '#include "foundation/value.hpp"\n\n'
            '#include "alpha/value.hpp"\n'
            '#include "zeta/value.hpp"\n'
        )

        cpp_system_header = source / "cpp_system_header.cpp"
        cpp_system_header.write_text("#include <vector>\n")
        result = run(
            formatter,
            root,
            "source/cpp_system_header.cpp",
            status=1,
        )
        assert "C headers ending in '.h'" in result.stderr
        cpp_system_header.unlink()
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
        (prelude / "example.h").write_text("typedef __UINT8_TYPE__ U8;\n")
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
            'const char* qualified = "Example::Data::Form::Value";\n'
            'const char* raw = R"(namespace Example::Module {})";\n'
            "// namespace Example::Module {}\n"
            "// Example::Data::Form::Value remains prose.\n"
            "/* namespace Example::Module::Detail appears in prose. */\n"
        )
        run(formatter, root, "source/masked.cpp")

        qualified = source / "qualified.cpp"
        qualified.write_text(
            "using namespace Example::Concept;\n"
            "auto representation() -> S32 {\n"
            "  return Example::Data::Form::first + "
            "Example::Data::Form::second;\n"
            "}\n"
        )
        result = run(formatter, root, "source/qualified.cpp", status=1)
        assert result.stderr.count("using namespace Example::Data;") == 1
        assert "architectural concept collision" in result.stderr
        qualified.unlink()

        imported = source / "imported.cpp"
        imported.write_text(
            "using namespace Example::Data;\n"
            "auto representation() -> S32 {\n"
            "  return Form::first;\n"
            "}\n"
        )
        run(formatter, root, "source/imported.cpp")

        paragraph = source / "paragraph.cpp"
        paragraph.write_text(
            "auto paragraph() -> S32 {\n"
            "  S32 value = 0;\n"
            "  value++;\n\n"
            "  S32 selected = value;\n"
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
            "auto update(S32* values) -> void {\n"
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
            "auto select() -> S32 {\n\n"
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
            if name == "deep.cpp":
                assert "using namespace Example::Module;" in result.stderr
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
            "S32 value;\n"
        )
        run(formatter, root, "source/accepted_comment.cpp")
        run(formatter, root, "--check", "source/accepted_comment.cpp")

        invalid_declarations = {
            "const_cast.cpp": (
                "auto expose(const S32* value) -> S32* {\n"
                "  return const_cast<S32*>(value);\n"
                "}\n"
            ),
            "mutable.hpp": "struct Value { mutable S32 state; };\n",
            "class.hpp": "class Forward;\n",
            "enum.hpp": "enum class Forward : U32;\n",
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
            "leading_return.cpp": "S32 value() { return 1; }\n",
            "deduced_return.cpp": "auto value() { return 1; }\n",
            "call_operator.cpp": (
                "struct Callable {\n"
                "  auto operator()() { return 1; }\n"
                "};\n"
            ),
            "index_operator.cpp": (
                "struct Indexed {\n"
                "  auto operator[](S32) { return 1; }\n"
                "};\n"
            ),
            "comparison_operator.cpp": (
                "struct Comparable {\n"
                "  auto operator==(const Comparable&) const { return true; }\n"
                "};\n"
            ),
            "digit_separator.cpp": (
                "auto first() -> S32 { return 1'000; }\n"
                "S32 second() { return 2; }\n"
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
            "auto allocate() -> S32* {\n"
            "  return new S32;\n"
            "}\n"
            "auto release(S32* value) -> void {\n"
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

        fixed_aliases = {
            "int8_t": "S8",
            "int16_t": "S16",
            "int32_t": "S32",
            "int64_t": "S64",
            "uint8_t": "U8",
            "uint16_t": "U16",
            "uint32_t": "U32",
            "uint64_t": "U64",
        }
        fixed_alias = source / "fixed_alias.cpp"
        fixed_alias.write_text(
            "".join(
                f"{alias} {canonical.lower()}_value = 0;\n"
                for alias, canonical in fixed_aliases.items()
            )
            + "std::uint64_t qualified_u64 = 0;\n"
        )
        result = run(
            formatter,
            root,
            "--check",
            "source/fixed_alias.cpp",
            status=1,
        )
        for alias in fixed_aliases:
            assert f"noncanonical numeric type '{alias}'" in result.stderr
        run(formatter, root, "source/fixed_alias.cpp")
        run(formatter, root, "--check", "source/fixed_alias.cpp")
        canonical = fixed_alias.read_text()
        for alias, replacement in fixed_aliases.items():
            assert alias not in canonical
            assert replacement in canonical
        assert "std::U64" not in canonical
        assert "U64 qualified_u64" in canonical

        standard_headers = source / "standard_headers.cpp"
        standard_headers.write_text(
            "#include <stdint.h>\n"
            '#include "inttypes.h"\n\n'
            'const char* text = "#include <stdint.h>";\n'
            "// #include <inttypes.h> remains source text.\n"
            "S32 value = 0;\n"
        )
        result = run(
            formatter,
            root,
            "--check",
            "source/standard_headers.cpp",
            status=1,
        )
        assert result.stderr.count("standard integer header") == 2
        run(formatter, root, "source/standard_headers.cpp")
        run(formatter, root, "--check", "source/standard_headers.cpp")
        canonical = standard_headers.read_text()
        assert '#include "inttypes.h"' not in canonical
        assert canonical.count("#include <stdint.h>") == 1
        assert "// #include <inttypes.h> remains source text." in canonical

        standard_macro = source / "standard_macro.cpp"
        standard_macro.write_text(
            "auto format(U64 value) -> void {\n"
            '  printf("%" PRIu64, value);\n'
            "}\n"
        )
        result = run(
            formatter,
            root,
            "source/standard_macro.cpp",
            status=1,
        )
        assert "standard integer macro 'PRIu64'" in result.stderr

        noncanonical_integer_types = [
            "int_least8_t",
            "int_least16_t",
            "int_least32_t",
            "int_least64_t",
            "uint_least8_t",
            "uint_least16_t",
            "uint_least32_t",
            "uint_least64_t",
            "int_fast8_t",
            "int_fast16_t",
            "int_fast32_t",
            "int_fast64_t",
            "uint_fast8_t",
            "uint_fast16_t",
            "uint_fast32_t",
            "uint_fast64_t",
            "intptr_t",
            "uintptr_t",
            "intmax_t",
            "uintmax_t",
        ]
        flexible_type = source / "flexible_type.cpp"
        flexible_type.write_text(
            "S32 canonical = 0;\n"
            "int flexible_int = 0;\n"
            "short flexible_short = 0;\n"
            "long flexible_long = 0;\n"
            "float flexible_float = 0;\n"
            "double flexible_double = 0;\n"
            "signed flexible_signed = 0;\n"
            "unsigned flexible_unsigned = 0;\n"
            "size_t flexible_size = 0;\n"
            "ptrdiff_t flexible_difference = 0;\n"
            + "".join(
                f"{name} integer_value_{index} = 0;\n"
                for index, name in enumerate(noncanonical_integer_types)
            )
        )
        result = run(
            formatter,
            root,
            "source/flexible_type.cpp",
            status=1,
        )
        for name in [
            "int",
            "short",
            "long",
            "float",
            "double",
            "signed",
            "unsigned",
            "size_t",
            "ptrdiff_t",
        ] + noncanonical_integer_types:
            assert f"noncanonical numeric type '{name}'" in result.stderr
        (root / "toolchain.json").write_text(
            '{\n  "flexible_type_files": [\n'
            '    "source/flexible_type.cpp"\n'
            "  ],\n"
            '  "raw_allocation_files": [\n'
            '    "source/raw_allocation.cpp"\n'
            "  ],\n"
            '  "standard_integer_files": [\n'
            '    "source/standard_macro.cpp"\n'
            "  ]\n}\n"
        )
        run(formatter, root, "source/flexible_type.cpp")
        run(formatter, root, "--check", "source/flexible_type.cpp")
        run(formatter, root, "--check", "source/standard_macro.cpp")

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
        allocation_macro.write_text("#define ALLOCATE() new S32\n")
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
                "auto value() -> S32 {\n"
                "  S32 value = 0;\n"
                "  value++;\n"
                "  S32 selected = value;\n"
                "  return selected;\n"
                "}\n"
            ),
            "block_statement.cpp": (
                "auto value(bool ready) -> S32 {\n"
                "  if (ready) {\n"
                "    return 1;\n"
                "  }\n"
                "  return 0;\n"
                "}\n"
            ),
            "block_block.cpp": (
                "auto value(bool first, bool second) -> S32 {\n"
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
            "auto select(bool first, bool second) -> S32 {\n"
            "  if (first) {\n"
            "    second = false;\n"
            "  }\n"
            "  for (S32 index = 0; index < 1; ++index) {\n"
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
            "auto select(bool first, bool second) -> S32 {\n"
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
                "auto select() -> S32 {\n"
                "#if FIRST\n"
                "  return FIRST;\n"
                "#else\n"
                "  return 0;\n"
                "#endif\n"
                "}\n"
            ),
            "definition.cpp": "S32 value;\n#define VALUE 1\nS32 selected;\n",
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
