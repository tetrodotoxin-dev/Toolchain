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


def comment_status(scanned, approved, warning, rejected, mean):
    return (
        "Comment quality:\n"
        f"  Scanned: {scanned}\n"
        f"  Approved: {approved}\n"
        f"  Warning: {warning}\n"
        f"  Rejected: {rejected}\n"
        f"  Mean comment score: {mean:.2f}/100\n"
    )


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

        configuration = root / ".vscode/.clang-format"
        result = run(
            formatter,
            root,
            "--export-configuration",
            ".vscode/.clang-format",
        )
        assert result.stdout == (
            "Generated format configuration at .vscode/.clang-format.\n"
        ), result.stdout
        generated = configuration.read_text()
        toolchain = generated.index("'^\"toolchain/")
        runtime = generated.index("'^\"runtime/")
        foundation = generated.index("'^\"foundation/")
        local = generated.index("'^\".*\"'")
        assert toolchain < runtime < foundation < local
        assert not (root / ".clang-format").exists()

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
        assert result.stdout == (
            comment_status(0, 0, 0, 0, 0)
            + "Formatted 1 source files.\n"
        ), result.stdout
        assert valid.read_text() == (
            '#include "valid.hpp"\n'
            "using namespace Example::Module;\n"
            "S32 main() {\n"
            "  return 0;\n"
            "}\n"
        ), valid.read_text()
        result = run(formatter, root, "--check", "source/valid.cpp")
        assert result.stdout == (
            comment_status(0, 0, 0, 0, 0)
            + "Checked 1 source files.\n"
        ), result.stdout

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

        abi_c_header = source / "abi_record.h"
        abi_c_header.write_text(
            "typedef struct example_record {\n"
            "  char value;\n"
            "#ifdef __cplusplus\n"
            "  constexpr example_record() : value(0) {}\n"
            "#endif\n"
            "} example_record;\n"
        )
        run(formatter, root, "source/abi_record.h")
        abi_c_header.unlink()

        legacy_c_header = source / "legacy.h"
        legacy_c_header.write_text(
            "typedef struct example_value { unsigned value; } example_value;\n"
            "#ifdef __cplusplus\n"
            "namespace Example {\nclass Value {};\n}\n"
            "#endif\n"
        )
        result = run(
            formatter,
            root,
            "source/legacy.h",
            status=1,
        )
        assert "standalone C++ namespaces and classes" in result.stderr
        legacy_c_header.unlink()

        owned = source / "example" / "module" / "folder"
        owned.mkdir(parents=True)
        owned_header = owned / "header.hpp"
        owned_header.write_text(
            "#pragma once\n"
            "namespace Example::Module::Folder {\n"
            "// Header supplies the public identity used to verify that nested\n"
            "// namespaces follow the complete source path.\n"
            "class Header {};\n}\n"
        )
        run(formatter, root, "source/example/module/folder/header.hpp")

        paired = source / "example" / "module" / "paired"
        paired.with_suffix(".hpp").write_text(
            "#pragma once\nnamespace Example::Module {\n"
            "// Paired is the declaration anchor for its implementation. The\n"
            "// identity remains in this header because source policy can then\n"
            "// prove that the implementation includes its matching header before\n"
            "// system dependencies.\n"
            "class Paired {};\n}\n"
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
            "#pragma once\nnamespace Example::Image {\n"
            "// Texture2D is the public image identity for this header. The numeric\n"
            "// suffix remains attached to its dimension letter because source\n"
            "// policy normalizes filename words before matching the declaration,\n"
            "// allowing texture_2d to name Texture2D without a path exception.\n"
            "class Texture2D {};\n}\n"
        )
        run(formatter, root, "source/example/image/texture_2d.hpp")

        compile_module = source / "example" / "compile"
        compile_module.mkdir(parents=True)
        source_location = compile_module / "source_location.hpp"
        source_location.write_text(
            "#pragma once\n"
            "namespace std {\n"
            "class source_location {\n"
            " public:\n"
            "  struct __impl {};\n"
            "};\n"
            "}\n"
            "namespace Example::Compile {\n"
            "// SourceLocation keeps the compiler location builtin behind the\n"
            "// public namespace derived from this header path.\n"
            "class SourceLocation {\n"
            " public:\n"
            "  static auto current(\n"
            "      const std::source_location::__impl* value = "
            "__builtin_source_location()) -> SourceLocation;\n"
            "};\n"
            "}\n"
        )
        run(formatter, root, "source/example/compile/source_location.hpp")

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
            "extra_object.hpp": (
                "#pragma once\n"
                "namespace Example::Module::Folder {\n"
                "class ExtraObject {};\n"
                "struct ParseFailure {};\n"
                "enum class FormatFailure { Invalid };\n"
                "}\n",
                "top level types nest under 'ExtraObject'",
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
            "// namespace Example::Module\n\n"
            "// Example::Data::Form::Value remains prose.\n"
            "/* namespace Example::Module::Detail */\n"
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

        selective_import = source / "selective_import.cpp"
        selective_import.write_text(
            "using Example::Data::Form;\n"
            "auto representation() -> Form;\n"
        )
        result = run(
            formatter,
            root,
            "source/selective_import.cpp",
            status=1,
        )
        assert "selective import 'using Example::Data::Form;'" in result.stderr
        assert "keep the namespace qualifier at each use" in result.stderr
        selective_import.unlink()

        type_alias = source / "type_alias.cpp"
        type_alias.write_text(
            "using namespace Example::Data;\n"
            "using FormAlias = Form;\n"
            "auto representation() -> FormAlias;\n"
        )
        run(formatter, root, "source/type_alias.cpp")

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

        first_type = source / "first_type.cpp"
        second_type = source / "second_type.cpp"
        first_type.write_text("class RepeatedFixture {};\n")
        second_type.write_text("class RepeatedFixture {};\n")
        result = run(
            formatter,
            root,
            "--check",
            "source/first_type.cpp",
            status=1,
        )
        assert "implementation type 'RepeatedFixture'" in result.stderr
        assert "move one shared definition to a header" in result.stderr
        first_type.unlink()
        second_type.unlink()

        invalid_comments = {
            "hyphen.cpp": "// Author-owned language.\nS32 value;\n",
            "semicolon.cpp": "// One clause; another clause.\nS32 value;\n",
            "em_dash.cpp": "// One clause — another clause.\nS32 value;\n",
            "en_dash.cpp": "// One clause – another clause.\nS32 value;\n",
            "filler.cpp": "// This simply returns the value.\nS32 value;\n",
            "obvious.cpp": "// This obviously preserves the value.\nS32 value;\n",
            "seamless.cpp": "// This seamlessly preserves the value.\nS32 value;\n",
        }
        for name, content in invalid_comments.items():
            path = source / name
            path.write_text(content)
            result = run(formatter, root, "source/" + name, status=1)
            assert "comment quality Reject" in result.stderr
            path.unlink()

        warned_comment = source / "warned_comment.cpp"
        warned_comment.write_text(
            "// The buffer stores each value.\n"
            "S32 value;\n"
        )
        result = run(formatter, root, "source/warned_comment.cpp")
        assert "comment quality Warn" in result.stderr
        assert comment_status(1, 0, 1, 0, 45) in result.stderr
        assert result.stdout == "Formatted 1 source files.\n", result.stdout
        warned_comment.unlink()

        rejected_comment = source / "rejected_comment.cpp"
        rejected_comment.write_text(
            "// This helper simply provides a robust and\n"
            "// flexible solution.\n"
            "S32 value;\n"
        )
        result = run(
            formatter,
            root,
            "source/rejected_comment.cpp",
            status=1,
        )
        assert result.stderr.count("comment quality Reject") == 1
        assert "  Scanned: 1\n" in result.stderr
        assert "  Rejected: 1\n" in result.stderr
        rejected_comment.unlink()

        inline_comment = source / "inline_comment.cpp"
        inline_comment.write_text(
            "S32 value; // This helper simply provides a robust solution.\n"
        )
        result = run(
            formatter,
            root,
            "source/inline_comment.cpp",
            status=1,
        )
        assert "comment quality Reject" in result.stderr
        assert "  Scanned: 1\n" in result.stderr
        assert "  Rejected: 1\n" in result.stderr
        inline_comment.unlink()

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
            "const_reference_cast.cpp": (
                "auto expose(S32& value) -> const S32& {\n"
                "  return static_cast<const S32&>(value);\n"
                "}\n"
            ),
            "reinterpret_cast.h": (
                "auto expose(void* value) -> U8* {\n"
                "  return reinterpret_cast<U8*>(value);\n"
                "}\n"
            ),
            "dynamic_cast.cpp": (
                "struct Base { virtual ~Base() = default; };\n"
                "struct Derived : Base {};\n"
                "auto expose(Base* value) -> Derived* {\n"
                "  return dynamic_cast<Derived*>(value);\n"
                "}\n"
            ),
            "bit_cast.cpp": (
                "auto expose(R32 value) -> U32 {\n"
                "  return __builtin_bit_cast(U32, value);\n"
                "}\n"
            ),
            "standard_bit_cast.cpp": (
                "auto expose(R32 value) -> U32 {\n"
                "  return std::bit_cast<U32>(value);\n"
                "}\n"
            ),
            "mutable.hpp": "struct Value { mutable S32 state; };\n",
            "class.hpp": "class Forward;\n",
            "namespaced_class.hpp": (
                "namespace Example::Module {\nclass Forward;\n}\n"
            ),
            "enum.hpp": "enum class Forward : U32;\n",
        }
        for name, content in invalid_declarations.items():
            path = source / name
            path.write_text(content)
            result = run(formatter, root, "source/" + name, status=1)
            assert (
                "data conversion boundary" in result.stderr
                or "owner contract" in result.stderr
                or "complete owner" in result.stderr
            )
            path.unlink()

        cast_owner = root / "perimortem"
        cast_owner.mkdir()
        (cast_owner / "MODULE.bazel").write_text(
            'module(name = "perimortem")\n'
        )
        cast_boundary = cast_owner / "source/perimortem/core"
        cast_boundary.mkdir(parents=True)
        data_header = cast_boundary / "data.hpp"
        data_source = (
            "#pragma once\n"
            "namespace Perimortem::Core {\n"
            "class Data {\n"
            " public:\n"
            "  template <typename target_type, typename source_type>\n"
            "  static auto cast(source_type* source) -> target_type* {\n"
            "    return reinterpret_cast<target_type*>(source);\n"
            "  }\n"
            "};\n"
            "}\n"
        )
        data_header.write_text(data_source)
        result = run(
            formatter,
            cast_owner,
            "source/perimortem/core/data.hpp",
            status=1,
        )
        assert "locked source changed" in result.stderr

        subprocess.run(
            ["git", "init", "--quiet"],
            cwd=cast_owner,
            check=True,
        )
        subprocess.run(
            ["git", "add", "MODULE.bazel", "source/perimortem/core/data.hpp"],
            cwd=cast_owner,
            check=True,
        )
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=Toolchain",
                "-c",
                "user.email=validation@toolchain.invalid",
                "commit",
                "--quiet",
                "-m",
                "Baseline",
            ],
            cwd=cast_owner,
            check=True,
        )
        result = run(
            formatter,
            cast_owner,
            "source/perimortem/core/data.hpp",
            status=1,
        )
        assert "locked source changed" in result.stderr
        assert "locked source has staged or unstaged edits" not in result.stderr

        data_header.write_text(data_source + "// Local edit.\n")
        result = run(
            formatter,
            cast_owner,
            "source/perimortem/core/data.hpp",
            status=1,
        )
        assert "locked source has staged or unstaged edits" in result.stderr

        subprocess.run(
            ["git", "add", "source/perimortem/core/data.hpp"],
            cwd=cast_owner,
            check=True,
        )
        result = run(
            formatter,
            cast_owner,
            "source/perimortem/core/data.hpp",
            status=1,
        )
        assert "locked source has staged or unstaged edits" in result.stderr

        other_header = cast_boundary / "other.hpp"
        other_header.write_text(data_source.replace("Data", "Other"))
        result = run(
            formatter,
            cast_owner,
            "source/perimortem/core/other.hpp",
            status=1,
        )
        assert "data conversion boundary" in result.stderr

        policy = source / "example" / "container" / "policy.hpp"
        policy.parent.mkdir(parents=True)
        complete_policy = (
            "#pragma once\n"
            "namespace Example::Container {\n"
            "// Policy owns one value while allowing its storage policy to change.\n"
            "// The policy provides the following required operations:\n"
            "//\n"
            "//  auto allocate(Count requested) -> S32*\n"
            "//\n"
            "//    Returns storage for at least the requested value count.\n"
            "//\n"
            "//  auto release(S32* values) -> void\n"
            "//\n"
            "//    Detaches the allocation after its current values are retired.\n"
            "template <typename policy_type>\n"
            "class Policy {\n"
            " public:\n"
            "  auto update() -> void {\n"
            "    S32* values = get_policy().allocate(1);\n"
            "    get_policy().release(values);\n"
            "  }\n"
            " private:\n"
            "  auto get_policy() -> policy_type&;\n"
            "};\n"
            "}\n"
        )
        policy.write_text(complete_policy)
        run(formatter, root, "source/example/container/policy.hpp")
        policy.write_text(
            complete_policy.replace(
                "//  auto release(S32* values) -> void\n"
                "//\n"
                "//    Detaches the allocation after its current values are retired.\n",
                "",
            )
        )
        result = run(
            formatter,
            root,
            "source/example/container/policy.hpp",
            status=1,
        )
        assert "incomplete policy extension contract" in result.stderr
        policy.write_text(complete_policy)

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
            "// Constructors defines the ordinary special members used to prove that\n"
            "// conversion operators do not require constructor rationale comments.\n"
            "class Constructors {\n"
            " public:\n"
            "  Constructors() = default;\n"
            "  ~Constructors() = default;\n"
            "  explicit operator bool() const { return true; }\n"
            "};\n"
        )
        run(formatter, root, "source/constructors.hpp")

        missing_primary_contract = source / "missing_primary_contract.hpp"
        missing_primary_contract.write_text(
            "class MissingPrimaryContract {\n"
            "};\n"
        )
        result = run(
            formatter,
            root,
            "source/missing_primary_contract.hpp",
            status=1,
        )
        assert "missing primary type contract" in result.stderr
        assert "(100/100)" in result.stderr
        missing_primary_contract.unlink()

        missing_explicit_comment = source / "missing_explicit_comment.hpp"
        missing_explicit_comment.write_text(
            "class MissingExplicitComment {\n"
            " public:\n"
            "  explicit MissingExplicitComment(S32 value) : value(value) {}\n"
            " private:\n"
            "  S32 value;\n"
            "};\n"
        )
        result = run(
            formatter,
            root,
            "source/missing_explicit_comment.hpp",
            status=1,
        )
        assert "unjustified explicit constructor" in result.stderr
        assert "(100/100)" in result.stderr
        missing_explicit_comment.unlink()

        unexplained_explicit = source / "unexplained_explicit.hpp"
        unexplained_explicit.write_text(
            "class UnexplainedExplicit {\n"
            " public:\n"
            "  // Stores the supplied scalar.\n"
            "  explicit UnexplainedExplicit(S32 value) : value(value) {}\n"
            " private:\n"
            "  S32 value;\n"
            "};\n"
        )
        result = run(
            formatter,
            root,
            "source/unexplained_explicit.hpp",
            status=1,
        )
        assert "unjustified explicit constructor" in result.stderr
        assert "(100/100)" in result.stderr
        unexplained_explicit.unlink()

        shared_explicit_comment = source / "shared_explicit_comment.hpp"
        shared_explicit_comment.write_text(
            "class SharedExplicitComment {\n"
            " public:\n"
            "  /* Construction syntax keeps scalar values from converting into an\n"
            "     owner when the caller intends to retain the scalar. */\n"
            "  explicit SharedExplicitComment(S32 value) : value(value) {}\n"
            "  explicit SharedExplicitComment(U32 value) : value(value) {}\n"
            " private:\n"
            "  U32 value;\n"
            "};\n"
        )
        result = run(
            formatter,
            root,
            "source/shared_explicit_comment.hpp",
            status=1,
        )
        assert result.stderr.count("unjustified explicit constructor") == 1
        shared_explicit_comment.unlink()

        explained_explicits = source / "explained_explicits.hpp"
        explained_explicits.write_text(
            "// ExplainedExplicits verifies that each conversion boundary carries\n"
            "// its own rationale even when constructors share one target type.\n"
            "class ExplainedExplicits {\n"
            " public:\n"
            "  // Explicit construction prevents a signed scalar from silently becoming\n"
            "  // an ExplainedExplicits value at an unrelated call boundary.\n"
            "  explicit ExplainedExplicits(S32 value) : value(value) {}\n"
            "  // Construction syntax keeps an unsigned scalar from implicitly becoming\n"
            "  // an ExplainedExplicits value at an unrelated call boundary.\n"
            "  explicit ExplainedExplicits(U32 value) : value(value) {}\n"
            " private:\n"
            "  U32 value;\n"
            "};\n"
        )
        run(formatter, root, "source/explained_explicits.hpp")
        run(formatter, root, "--check", "source/explained_explicits.hpp")

        deleted_operation = source / "deleted_operation.hpp"
        deleted_operation.write_text(
            "// DeletedOperation exists to verify that an unavailable copy path\n"
            "// does not create a conversion boundary requiring rationale. Its\n"
            "// deleted constructor is a compile time prohibition rather than a\n"
            "// callable state transition.\n"
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
        assert "approved in Toolchain's source policy" in result.stderr
        (root / "toolchain.json").write_text(
            '{\n  "raw_allocation_files": [\n'
            '    "source/raw_allocation.cpp"\n'
            "  ]\n}\n"
        )
        result = run(
            formatter,
            root,
            "source/raw_allocation.cpp",
            status=2,
        )
        assert (
            "Toolchain source policy owns exceptional project paths"
            in result.stderr
        )
        (root / "toolchain.json").unlink()
        raw_allocation.unlink()

        copied_path = source / "perimortem/memory/allocator/global.cpp"
        copied_path.parent.mkdir(parents=True)
        copied_path.write_text(
            "auto allocate() -> void* {\n"
            "  return malloc(1);\n"
            "}\n"
        )
        result = run(
            formatter,
            root,
            "source/perimortem/memory/allocator/global.cpp",
            status=1,
        )
        assert "approved in Toolchain's source policy" in result.stderr
        copied_path.unlink()

        toolchain_root = root / "toolchain_policy"
        lifetime = toolchain_root / "source/toolchain/memory/lifetime.hpp"
        lifetime.parent.mkdir(parents=True)
        (toolchain_root / "MODULE.bazel").write_text(
            'module(name = "tetro_toolchain")\n'
        )
        toolchain_configuration = toolchain_root / ".vscode/.clang-format"
        run(
            formatter,
            toolchain_root,
            "--export-configuration",
            ".vscode/.clang-format",
        )
        assert toolchain_configuration.exists()

        lifetime.write_text(
            "// # Toolchain\n"
            "// Copyright (c) 2023-present Matt Kaes and contributors\n\n"
            "#pragma once\n\n"
            "namespace Toolchain {\n"
            "auto allocate() -> S32* { return new S32; }\n"
            "}\n"
        )
        result = run(
            formatter,
            toolchain_root,
            "source/toolchain/memory/lifetime.hpp",
            status=1,
        )
        assert "approved in Toolchain's source policy" in result.stderr

        lifetime.write_text(
            "// # Toolchain\n"
            "// Copyright (c) 2023-present Matt Kaes and contributors\n\n"
            "#pragma once\n\n"
            "namespace Toolchain::Memory {\n\n"
            "// Lifetime begins values in storage supplied by the caller.\n"
            "class Lifetime {\n"
            " public:\n"
            "  static constexpr auto construct(void* allocation) -> S32* {\n"
            "    return new (allocation) S32();\n"
            "  }\n"
            "};\n\n"
            "}  // namespace Toolchain::Memory\n"
        )
        result = run(
            formatter,
            toolchain_root,
            "source/toolchain/memory/lifetime.hpp",
            status=1,
        )
        assert "approved in Toolchain's source policy" in result.stderr

        lifetime.write_text(
            "// # Toolchain\n"
            "// Copyright (c) 2023-present Matt Kaes and contributors\n\n"
            "#pragma once\n\n"
            "namespace Toolchain::Memory {\n\n"
            "// Lifetime begins values in storage supplied by the caller.\n"
            "class Lifetime {\n"
            " public:\n"
            "  static constexpr auto construct(void* address) -> S32* {\n"
            "    return new (address) S32();\n"
            "  }\n"
            "};\n\n"
            "}  // namespace Toolchain::Memory\n"
        )
        run(
            formatter,
            toolchain_root,
            "source/toolchain/memory/lifetime.hpp",
        )

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
            "// The literal `#include <inttypes.h>` remains source text because\n"
            "// lexical policy masks comments.\n"
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
        assert "// The literal `#include <inttypes.h>` remains source text" in canonical

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
        flexible_type.unlink()
        standard_macro.unlink()

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
        assert "approved in Toolchain's source policy" in result.stderr
        unregistered_allocation.unlink()

        allocation_macro = source / "allocation_macro.cpp"
        allocation_macro.write_text("#define ALLOCATE() new S32\n")
        result = run(
            formatter,
            root,
            "source/allocation_macro.cpp",
            status=1,
        )
        assert "approved in Toolchain's source policy" in result.stderr
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

        body_boundaries = source / "body_boundaries.hpp"
        body_boundaries.write_text(
            "// BodyBoundaries places every special member form in one type so\n"
            "// formatting can distinguish inline bodies from multiline state\n"
            "// transitions and preserve a declaration boundary between them.\n"
            "class BodyBoundaries {\n"
            " public:\n"
            "  BodyBoundaries(S32 value) : value(value) {}\n"
            "  BodyBoundaries(const BodyBoundaries& source) : value(source.value) {\n"
            "    value++;\n"
            "  }\n"
            "  BodyBoundaries(BodyBoundaries&& source) {\n"
            "    value = source.value;\n"
            "    source.value = 0;\n"
            "  }\n"
            "  auto operator=(const BodyBoundaries& source) -> BodyBoundaries& {\n"
            "    value = source.value;\n"
            "    return *this;\n"
            "  }\n"
            "  ~BodyBoundaries() { value = 0; }\n"
            " private:\n"
            "  S32 value;\n"
            "};\n"
        )
        result = run(
            formatter,
            root,
            "--check",
            "source/body_boundaries.hpp",
            status=1,
        )
        assert "multiline braced entities" in result.stderr
        run(formatter, root, "source/body_boundaries.hpp")
        formatted_boundaries = body_boundaries.read_text()
        assert "value(value) {}\n  BodyBoundaries" in formatted_boundaries
        assert "    value++;\n  }\n\n  BodyBoundaries" in formatted_boundaries
        assert "  }\n\n  auto operator=" in formatted_boundaries, repr(
            formatted_boundaries
        )
        assert "    return *this;\n  }\n\n  ~BodyBoundaries" in formatted_boundaries
        run(formatter, root, "source/body_boundaries.hpp")
        assert body_boundaries.read_text() == formatted_boundaries
        run(formatter, root, "--check", "source/body_boundaries.hpp")

        requires_expression = source / "requires_expression.hpp"
        requires_expression.write_text(
            "template <typename Type>\n"
            "  requires requires(const Type& value) {\n"
            "    value.get_data();\n"
            "    value.get_capacity();\n"
            "    value.get_size();\n"
            "  }\n"
            "inline auto size(const Type& value) -> Count {\n"
            "  return value.get_size();\n"
            "}\n"
        )
        run(formatter, root, "source/requires_expression.hpp")
        formatted_requires = requires_expression.read_text()
        assert "  }\ninline auto size" in formatted_requires, repr(formatted_requires)
        run(formatter, root, "--check", "source/requires_expression.hpp")

        type_boundaries = source / "type_boundaries.hpp"
        type_boundaries.write_text(
            "struct FirstType {\n"
            "  S32 first;\n"
            "  S32 second;\n"
            "};\n"
            "// Second type\n"
            "struct SecondType {\n"
            "  S32 value;\n"
            "};\n"
        )
        result = run(
            formatter,
            root,
            "--check",
            "source/type_boundaries.hpp",
            status=1,
        )
        assert "multiline braced entities" in result.stderr
        run(formatter, root, "source/type_boundaries.hpp")
        assert "};\n\n// Second type\nstruct SecondType" in type_boundaries.read_text()
        run(formatter, root, "--check", "source/type_boundaries.hpp")

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

        default_source = source / "default.cpp"
        default_source.write_text("auto value()->S32{return 1;}\n")
        result = run(formatter, root)
        assert default_source.read_text() == (
            "auto value() -> S32 {\n"
            "  return 1;\n"
            "}\n"
        )
        assert "Comment quality:\n" in result.stdout + result.stderr
        assert "Formatted " in result.stdout
        result = run(formatter, root, "../outside.cpp", status=2)
        assert "Source path leaves the workspace" in result.stderr
        result = run(formatter, root, "source", status=2)
        assert "Expected one C or C++ source file" in result.stderr
