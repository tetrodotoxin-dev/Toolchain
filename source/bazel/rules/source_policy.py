# Copyright (c) 2023-present Matt Kaes and contributors

"""Validate C and C++ structure that clang-format leaves semantic."""

import re


HEADERS = {".h", ".hpp"}
IMPLEMENTATIONS = {".cpp"}

USING_NAMESPACE = re.compile(r"\busing\s+namespace\s+([^;]+);")
SELECTIVE_USING = re.compile(
    r"\busing\s+"
    r"((?:[A-Za-z_][A-Za-z0-9_]*\s*::\s*)+"
    r"[A-Za-z_][A-Za-z0-9_]*)\s*;"
)
MODULE_NAMESPACE = re.compile(
    r"[A-Za-z_][A-Za-z0-9_]*\s*::\s*[A-Za-z_][A-Za-z0-9_]*"
)
NAMESPACE_DECLARATION = re.compile(
    r"\b(?:inline\s+)?namespace"
    r"(?:\s+[A-Za-z_][A-Za-z0-9_]*(?:\s*::\s*[A-Za-z_][A-Za-z0-9_]*)*)?"
    r"\s*(?:\{|=)"
)
IMPLEMENTATION_TYPE_DEFINITION = re.compile(
    r"(?m)^[ \t]*(?:class|struct|union)\s+([A-Za-z_][A-Za-z0-9_]*)\b|"
    r"^[ \t]*enum\s+(?:class\s+|struct\s+)?([A-Za-z_][A-Za-z0-9_]*)\b"
)
RAW_STRING = re.compile(r'(?:u8|u|U|L)?R"([^ ()\\\t\r\n]{0,16})\(')
FORWARD_DECLARATION = re.compile(
    r"\b(?:class|struct|union)\s+[A-Za-z_][A-Za-z0-9_]*\s*;|"
    r"\benum(?:\s+(?:class|struct))?\s+[A-Za-z_][A-Za-z0-9_]*"
    r"(?:\s*:\s*[^;{]+)?\s*;"
)
HEADER_NAMESPACE = re.compile(
    r"\bnamespace\s+([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)\s*\{"
)
PLATFORM_CONDITION = re.compile(
    r"\b(?:PERI_(?:LINUX|WINDOWS|WASM|MACOS|FREEBSD)|"
    r"_WIN32|__linux__|__APPLE__|__EMSCRIPTEN__|__FreeBSD__)\b"
)
PLATFORM_INCLUDE = re.compile(
    r"^\s*#\s*include\s*[<\"](?:windowsx?\.h|unistd\.h|poll\.h|dlfcn\.h|"
    r"sys/|linux/|wayland|mach/|CoreFoundation/|emscripten(?:\.h|/))"
)
SYSTEM_INCLUDE = re.compile(r"^\s*#\s*include\s*<([^>]+)>")
NAMED_CAST = re.compile(
    r"\b(?:const|dynamic|reinterpret|static)_cast\s*<|"
    r"\bstd\s*::\s*bit_cast\s*<|"
    r"\b__builtin_bit_cast\s*\("
)
STANDARD_INTEGER_INCLUDE = re.compile(
    r'^[ \t]*#[ \t]*include[ \t]*[<"](?:inttypes|stdint)\.h[>"]'
    r"[ \t]*(?://.*)?(?:\r?\n|$)",
    re.MULTILINE,
)
STANDARD_INTEGER_MACRO = re.compile(
    r"\b(?:"
    r"(?:PRI|SCN)[diouxX](?:8|16|32|64|LEAST(?:8|16|32|64)|"
    r"FAST(?:8|16|32|64)|MAX|PTR)|"
    r"(?:U?INT(?:8|16|32|64)|U?INT_(?:LEAST|FAST)(?:8|16|32|64)|"
    r"U?INTPTR|U?INTMAX|SIZE|PTRDIFF|SIG_ATOMIC|WCHAR|WINT)_"
    r"(?:MIN|MAX|C)"
    r")\b"
)
CONDITIONAL_DIRECTIVES = {
    "if",
    "ifdef",
    "ifndef",
    "elif",
    "elifdef",
    "elifndef",
    "else",
    "endif",
}
PREPROCESSOR_CONTENT = {
    "define",
    "error",
    "include",
    "pragma",
    "undef",
}
TOKENS = re.compile(
    r"<=>|<<=|>>=|->\*|::|->|&&|\|\||\+\+|--|<<|>>|"
    r"==|!=|<=|>=|\+=|-=|\*=|/=|%=|&=|\|=|\^=|"
    r"[A-Za-z_][A-Za-z0-9_]*|"
    r"[{}()\[\];<>=,*&:.?~!+\-/|%^]"
)
CONTROL = {"if", "for", "while", "switch", "do", "try", "else", "catch"}
STATEMENTS = {"break", "co_return", "continue", "delete", "goto", "return", "throw"}
DECLARATIONS = {
    "auto",
    "class",
    "const",
    "consteval",
    "constexpr",
    "constinit",
    "enum",
    "extern",
    "long",
    "register",
    "short",
    "signed",
    "static",
    "static_assert",
    "struct",
    "thread_local",
    "typedef",
    "union",
    "unsigned",
    "using",
    "volatile",
}
RAW_ALLOCATORS = {
    "VirtualAlloc",
    "VirtualFree",
    "HeapAlloc",
    "HeapFree",
    "MapViewOfFile",
    "UnmapViewOfFile",
    "aligned_alloc",
    "calloc",
    "free",
    "malloc",
    "mmap",
    "mremap",
    "munmap",
    "posix_memalign",
    "realloc",
}
# Toolchain owns exceptional source paths so each foundational capability is
# reviewed together with the policy that protects it.
APPROVED_RAW_ALLOCATION_FILES = {
    ("perimortem", "source/perimortem/memory/allocator/bibliotheca.cpp"),
    ("perimortem", "source/perimortem/memory/allocator/global.cpp"),
    ("toolchain", "source/toolchain/compile/allocation.hpp"),
}
APPROVED_PLACEMENT_NEW_FILES = {
    ("toolchain", "source/toolchain/memory/lifetime.hpp"),
}
APPROVED_NAMED_CAST_FILES = {
    ("perimortem", "source/perimortem/core/data.hpp"),
}
APPROVED_FLEXIBLE_TYPE_FILES = {
    ("toolchain", "source/toolchain/toolchain.h"),
}
APPROVED_STANDARD_INTEGER_FILES = set()
CANONICAL_TYPE_SUBSTITUTIONS = {
    "int8_t": "S8",
    "int16_t": "S16",
    "int32_t": "S32",
    "int64_t": "S64",
    "uint8_t": "U8",
    "uint16_t": "U16",
    "uint32_t": "U32",
    "uint64_t": "U64",
}
NONCANONICAL_INTEGER_TYPES = {
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
}
FLEXIBLE_TYPES = (
    set(CANONICAL_TYPE_SUBSTITUTIONS) | NONCANONICAL_INTEGER_TYPES | {
        "double",
        "float",
        "int",
        "long",
        "ptrdiff_t",
        "short",
        "signed",
        "size_t",
        "unsigned",
    }
)


def lexical(source):
    """Preserve source positions while collecting comments and masking text."""
    output = list(source)
    comments = []
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            end = len(source) if end < 0 else end
            comments.append((index, end, source[index + 2:end]))
        elif source.startswith("/*", index):
            end = source.find("*/", index + 2)
            end = len(source) if end < 0 else end + 2
            content_end = end - 2 if source[end - 2:end] == "*/" else end
            comments.append((index, end, source[index + 2:content_end]))
        else:
            raw = RAW_STRING.match(source, index)
            if raw:
                marker = ")" + raw.group(1) + '"'
                found = source.find(marker, raw.end())
                end = len(source) if found < 0 else found + len(marker)
            elif (
                source[index] == "'"
                and index > 0
                and index + 1 < len(source)
                and source[index - 1].isalnum()
                and source[index + 1].isalnum()
            ):
                index += 1
                continue
            elif source[index] in "\"'":
                quote = source[index]
                end = index + 1
                while end < len(source):
                    if source[end] == "\\":
                        end += 2
                    elif source[end] == quote:
                        end += 1
                        break
                    else:
                        end += 1
            else:
                index += 1
                continue

        for position in range(index, min(end, len(source))):
            if output[position] != "\n":
                output[position] = " "
        index = end
    return "".join(output), comments


def line_at(source, offset):
    return source.count("\n", 0, offset) + 1


def implementation_type_definitions(path):
    """Find namespace-scope type definitions emitted by one implementation."""
    if path.suffix not in IMPLEMENTATIONS:
        return []

    source = path.read_text()
    code, _ = lexical(source)
    definitions = []
    for match in IMPLEMENTATION_TYPE_DEFINITION.finditer(code):
        if code.count("{", 0, match.start()) != code.count("}", 0, match.start()):
            continue

        opening = code.find("{", match.end())
        terminator = code.find(";", match.end())
        if opening < 0 or (terminator >= 0 and terminator < opening):
            continue

        definitions.append(
            (match.group(1) or match.group(2), line_at(source, match.start()))
        )
    return definitions


def duplicate_implementation_type_errors(paths, selected):
    """Reject different implementation files that publish one type identity."""
    definitions = {}
    for path in paths:
        for name, line in implementation_type_definitions(path):
            definitions.setdefault(name, []).append((path, line))

    selected = set(selected)
    errors = []
    for name, locations in sorted(definitions.items()):
        owners = {path for path, _ in locations}
        if len(owners) < 2:
            continue

        rendered = ", ".join(
            f"{path}:{line}" for path, line in sorted(locations)
        )
        for path, line in locations:
            if path in selected:
                errors.append(
                    f"{path}:{line}: implementation type '{name}' is defined in "
                    f"multiple .cpp files ({rendered}); move one shared definition "
                    "to a header or give distinct fixtures distinct names"
                )
    return errors


def pascal_name(value):
    words = []
    for word in value.split("_"):
        converted = word[:1].upper() + word[1:]
        converted = re.sub(
            r"(?<=\d)[a-z]", lambda match: match.group(0).upper(), converted
        )
        words.append(converted)
    return "".join(words)


def public_header_identity(path):
    parts = path.parts
    source = max(
        (index for index, part in enumerate(parts) if part == "source"),
        default=-1,
    )
    relative = parts[source + 1 :]
    if (
        source < 0
        or path.suffix != ".hpp"
        or len(relative) < 2
        or relative[0] == "implementation"
    ):
        return None
    namespace = "::".join(pascal_name(part) for part in relative[:-1])
    return namespace, pascal_name(path.stem)


def namespace_owns(code, declaration, object_declaration):
    opening = code.find("{", declaration.start(), declaration.end())
    if opening < 0:
        return False
    depth = 1
    closing = opening + 1
    while closing < len(code) and depth:
        depth += code[closing] == "{"
        depth -= code[closing] == "}"
        closing += 1
    for owned in object_declaration.finditer(code, opening + 1, closing - 1):
        prefix = code[opening + 1 : owned.start()]
        if prefix.count("{") == prefix.count("}"):
            return True
    return False


def source_location_extension(expected_namespace, expected_object, namespace, code):
    return (
        namespace == "std"
        and expected_object == "SourceLocation"
        and expected_namespace.endswith("::Compile")
        and re.search(r"\bclass\s+source_location\b", code)
        and re.search(r"\bstruct\s+__impl\b", code)
        and "__builtin_source_location" in code
    )


def compiler_prelude(path, expected_object, source):
    identity = public_header_identity(path)
    if not identity:
        return False
    parts = path.parts
    source_index = max(
        index for index, part in enumerate(parts) if part == "source"
    )
    relative = parts[source_index + 1 :]
    c_header = path.with_suffix(".h")
    c_include = "/".join(relative[:-1] + (c_header.name,))
    return (
        expected_object == pascal_name(relative[0])
        and c_header.is_file()
        and f'#include "{c_include}"' in source
    )


def header_identity_errors(path, source, code):
    """Match each public C++ header to its namespace and primary object."""
    identity = public_header_identity(path)
    if not identity:
        return []
    expected_namespace, expected_object = identity
    prelude = compiler_prelude(path, expected_object, source)
    errors = []
    if not re.search(r"^#pragma\s+once\s*$", source, re.MULTILINE):
        errors.append(f"{path}:1: public C++ headers begin with '#pragma once'")
    namespaces = list(HEADER_NAMESPACE.finditer(code))
    for declaration in namespaces:
        namespace = declaration.group(1)
        if namespace != expected_namespace and not source_location_extension(
            expected_namespace, expected_object, namespace, code
        ):
            errors.append(
                f"{path}:{line_at(source, declaration.start())}: public header namespaces match '{expected_namespace}'"
            )
    if not namespaces and not prelude:
        errors.append(
            f"{path}:1: public header namespace is '{expected_namespace}'"
        )

    object_declaration = re.compile(
        r"\b(?:class|struct|union)\s+" + re.escape(expected_object) + r"\b|"
        r"\benum\s+(?:class\s+|struct\s+)?"
        + re.escape(expected_object)
        + r"\b"
    )
    owns_object = any(
        declaration.group(1) == expected_namespace
        and namespace_owns(code, declaration, object_declaration)
        for declaration in namespaces
    )
    if not owns_object and not prelude:
        errors.append(
            f"{path}:1: public header primary object is '{expected_object}'"
        )
    return errors


def namespace_errors(path, source, code):
    errors = []
    for match in USING_NAMESPACE.finditer(code):
        line = line_at(source, match.start())
        if path.suffix in HEADERS:
            errors.append(
                f"{path}:{line}: headers express namespace ownership with declarations and qualified names"
            )
        elif path.suffix in IMPLEMENTATIONS and not MODULE_NAMESPACE.fullmatch(
            match.group(1).strip()
        ):
            parts = re.findall(
                r"[A-Za-z_][A-Za-z0-9_]*", match.group(1)
            )
            correction = (
                f"; replace this declaration with 'using namespace "
                f"{parts[0]}::{parts[1]};'"
                if len(parts) > 2
                else ""
            )
            errors.append(
                f"{path}:{line}: implementation imports use "
                f"'using namespace SDK::Module;'{correction}"
            )

    if path.suffix in IMPLEMENTATIONS:
        for match in SELECTIVE_USING.finditer(code):
            name = re.sub(r"\s+", "", match.group(1))
            errors.append(
                f"{path}:{line_at(source, match.start())}: selective import "
                f"'using {name};' hides namespace ownership; keep the "
                "namespace qualifier at each use"
            )

    if path.suffix in IMPLEMENTATIONS:
        for match in NAMESPACE_DECLARATION.finditer(code):
            errors.append(
                f"{path}:{line_at(source, match.start())}: implementation namespace access uses 'using namespace SDK::Module;'"
            )
    return errors


def qualified_namespace_errors(path, source, code, namespace_roots):
    """Require implementation references to enter through module imports."""
    if path.suffix not in IMPLEMENTATIONS or not namespace_roots:
        return []
    imported = [match.span() for match in USING_NAMESPACE.finditer(code)]
    roots = "|".join(re.escape(root) for root in sorted(namespace_roots))
    qualified = re.compile(
        r"\b(" + roots + r")\s*::\s*([A-Za-z_][A-Za-z0-9_]*)\s*::"
    )
    errors = []
    reported = set()
    for match in qualified.finditer(code):
        if any(start <= match.start() < end for start, end in imported):
            continue
        module = (match.group(1), match.group(2))
        if module in reported:
            continue
        reported.add(module)
        namespace = "::".join(module)
        errors.append(
            f"{path}:{line_at(source, match.start())}: import '{namespace}' with "
            f"'using namespace {namespace};' and remove the '{namespace}::' "
            "prefix from references in this implementation. A naming collision "
            "between module imports exposes an architectural concept collision; "
            "rename the concept or place the conflicting class in its owning module"
        )
    return errors


def implementation_header_errors(path, root, source):
    """Require an implementation's matching header as its first local include."""
    if path.suffix != ".cpp":
        return []
    header = path.with_suffix(".hpp")
    if not header.is_file():
        return []
    source_root = root / "source"
    if header.is_relative_to(source_root):
        expected = header.relative_to(source_root).as_posix()
    else:
        expected = header.relative_to(root).as_posix()
    first = re.search(
        r'^\s*#\s*include\s+([<"][^>"]+[>"])', source, re.MULTILINE
    )
    if first and first.group(1) == f'"{expected}"':
        return []
    return [
        f'{path}:1: implementation begins with its matching header "{expected}"'
    ]


def platform_header_errors(path, source):
    """Keep target selection inside implementation sources."""
    if path.suffix != ".hpp":
        return []
    errors = []
    for line, text in enumerate(source.splitlines(), 1):
        if PLATFORM_INCLUDE.search(text):
            errors.append(
                f"{path}:{line}: public headers include target independent SDK contracts"
            )
        current = directive(text)
        if current in {"if", "ifdef", "ifndef", "elif", "elifdef", "elifndef"}:
            if PLATFORM_CONDITION.search(text):
                errors.append(
                    f"{path}:{line}: public headers express one target independent contract"
                )
    return errors


def system_include_errors(path, source, code):
    """Keep system includes on the compact C header surface."""
    errors = []
    for line, text in enumerate(code.splitlines(), 1):
        include = SYSTEM_INCLUDE.match(text)
        if include and not include.group(1).endswith(".h"):
            errors.append(
                f"{path}:{line}: system includes use C headers ending in '.h'; "
                "C++ library headers expand the compilation surface"
            )
    return errors


def declaration_errors(path, root, project, source, code):
    """Keep C++ ownership on complete declarations and ordinary state."""
    if path.suffix not in HEADERS | IMPLEMENTATIONS:
        return []
    errors = []
    if not approved_file(path, root, project, APPROVED_NAMED_CAST_FILES):
        for match in NAMED_CAST.finditer(code):
            errors.append(
                f"{path}:{line_at(source, match.start())}: named casts use the owning project's reviewed data conversion boundary"
            )
    for match in re.finditer(r"\bmutable\b", code):
        errors.append(
            f"{path}:{line_at(source, match.start())}: state changing operations use their owner contract"
        )
    for match in FORWARD_DECLARATION.finditer(code):
        errors.append(
            f"{path}:{line_at(source, match.start())}: declarations include their complete owner"
        )
    return errors


def enclosing_executable(tokens, index, braces, parentheses):
    return any(
        opening < index < closing
        and executable_scope(tokens, opening, parentheses)
        for opening, closing in braces.items()
        if opening < closing
    )


def enclosing_type(tokens, index, braces):
    containing = [
        opening
        for opening, closing in braces.items()
        if opening < closing and opening < index < closing
    ]
    if not containing:
        return ""
    opening = max(containing)
    start = opening - 1
    while start >= 0 and tokens[start][0] not in {";", "{", "}"}:
        start -= 1
    declaration = [token for token, _, _ in tokens[start + 1 : opening]]
    for keyword in ("class", "struct", "union"):
        if keyword in declaration:
            position = declaration.index(keyword) + 1
            if position < len(declaration):
                return declaration[position]
    return ""


def parameter_declarations(tokens):
    """Recognize the declaration shape of one C++ parameter sequence."""
    if not tokens:
        return True
    parts = []
    start = 0
    angle_depth = 0
    parenthesis_depth = 0
    bracket_depth = 0
    for index, token in enumerate(tokens):
        angle_depth += token == "<"
        angle_depth -= token == ">"
        parenthesis_depth += token == "("
        parenthesis_depth -= token == ")"
        bracket_depth += token == "["
        bracket_depth -= token == "]"
        if (
            token == ","
            and angle_depth == 0
            and parenthesis_depth == 0
            and bracket_depth == 0
        ):
            parts.append(tokens[start:index])
            start = index + 1
    parts.append(tokens[start:])
    builtins = {
        "bool",
        "char",
        "double",
        "float",
        "int",
        "long",
        "short",
        "signed",
        "unsigned",
        "void",
        "wchar_t",
    }
    for part in parts:
        if "=" in part:
            part = part[: part.index("=")]
        words = [
            token
            for token in part
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token)
        ]
        if len(words) >= 2:
            continue
        if len(words) == 1 and (
            words[0] in builtins
            or words[0] in {"type", "value_type"}
            or words[0].endswith("_type")
            or words[0][:1].isupper()
            or "*" in part
            or "&" in part
            or "&&" in part
        ):
            continue
        return False
    return True


def executable_signature(tokens, brace, parentheses):
    """Identify a function body from the declaration before its opening brace."""
    if brace == 0:
        return False
    previous = tokens[brace - 1][0]
    if previous in {"else", "try", "do"} or previous == "]":
        return True
    start = brace - 1
    while start >= 0 and tokens[start][0] not in {";", "{", "}"}:
        start -= 1
    signature = [token for token, _, _ in tokens[start + 1 : brace]]
    if not signature or first_word(tokens[start + 1 : brace]) in {
        "class",
        "enum",
        "namespace",
        "struct",
        "union",
    }:
        return False
    return any(
        opening > start
        and closing < brace
        and parameter_declarations(
            [token for token, _, _ in tokens[opening + 1 : closing]]
        )
        for opening, closing in parentheses.items()
        if opening < closing
    )


def trailing_return_errors(path, source, code):
    """Require explicit C++ function returns after the parameter list."""
    if path.suffix not in {".cpp", ".hpp"}:
        return []
    tokens = code_tokens(source, code)
    parentheses = pairs(tokens, "(", ")")
    brackets = pairs(tokens, "[", "]")
    braces = pairs(tokens, "{", "}")
    errors = []
    for opening in sorted(index for index in parentheses if index < parentheses[index]):
        nested_parameter = any(
            parent < opening < closing
            for parent, closing in parentheses.items()
            if parent < closing
        )
        if (
            opening == 0
            or nested_parameter
            or enclosing_executable(tokens, opening, braces, parentheses)
            or any(
                left < opening < right
                for left, right in brackets.items()
                if left < right
            )
            or (opening >= 2 and tokens[opening - 2][0] in {".", ",", ":"})
        ):
            continue
        closing = parentheses[opening]
        if (
            tokens[opening - 1][0] == "operator"
            and closing + 1 < len(tokens)
            and tokens[closing + 1][0] == "("
        ):
            continue
        name_index = opening - 1
        name = tokens[name_index][0]
        if name == ")":
            symbol = parentheses.get(name_index)
            if (
                symbol is not None
                and symbol > 0
                and tokens[symbol - 1][0] == "operator"
            ):
                name_index = symbol - 1
                name = "operator"
        elif name == "]":
            symbol = brackets.get(name_index)
            if (
                symbol is not None
                and symbol > 0
                and tokens[symbol - 1][0] == "operator"
            ):
                name_index = symbol - 1
                name = "operator"
        elif (
            name
            in {
                "!",
                "!=",
                "%",
                "%=",
                "&",
                "&&",
                "&=",
                "*",
                "*=",
                "+",
                "++",
                "+=",
                "-",
                "--",
                "-=",
                "->",
                "->*",
                "/",
                "/=",
                "<",
                "<<",
                "<<=",
                "<=",
                "<=>",
                "=",
                "==",
                ">",
                ">=",
                ">>",
                ">>=",
                "^",
                "^=",
                "|",
                "|=",
                "||",
                "~",
            }
            and name_index > 0
            and tokens[name_index - 1][0] == "operator"
        ):
            name_index -= 1
            name = "operator"
        if (
            name != "operator"
            and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name)
            or name in CONTROL
            or name == "EXPORTED"
            or name.isupper()
            or name
            in {
                "alignas",
                "decltype",
                "noexcept",
                "requires",
                "sizeof",
                "static_assert",
            }
            or name == "main"
        ):
            continue
        if (
            name == "operator"
            and name_index == opening - 1
            and closing + 1 < len(tokens)
            and tokens[closing + 1][0] == "("
        ):
            continue
        end = closing + 1
        while end < len(tokens) and tokens[end][0] not in {";", "{", "}"}:
            end += 1
        if end == len(tokens):
            continue
        suffix = [token for token, _, _ in tokens[closing + 1 : end]]
        start = name_index - 1
        while start >= 0 and tokens[start][0] not in {";", "{", "}"}:
            start -= 1
        prefix = [token for token, _, _ in tokens[start + 1 : name_index]]
        angle_depth = 0
        for token in prefix:
            angle_depth += token == "<"
            angle_depth -= token == ">"
        if angle_depth > 0 or "." in prefix or "requires" in prefix:
            continue
        owner = enclosing_type(tokens, opening, braces)
        qualified_constructor = (
            opening >= 4
            and tokens[opening - 2][0] == "::"
            and tokens[opening - 3][0] == name
        )
        if (
            name == owner
            or qualified_constructor
            or (
                name != "operator"
                and opening >= 2
                and tokens[opening - 2][0] in {"operator", "~"}
            )
        ):
            continue
        significant = [
            token
            for token in prefix
            if token
            not in {
                "C_LINKAGE",
                "EXPORTED",
                "consteval",
                "constexpr",
                "explicit",
                "extern",
                "final",
                "friend",
                "inline",
                "override",
                "static",
                "virtual",
            }
        ]
        if opening >= 2 and tokens[opening - 2][0] == "::":
            owner_prefix = list(prefix)
            while (
                len(owner_prefix) >= 2
                and owner_prefix[-1] == "::"
                and re.fullmatch(
                    r"[A-Za-z_][A-Za-z0-9_]*", owner_prefix[-2]
                )
            ):
                owner_prefix = owner_prefix[:-2]
            owner_significant = [
                token
                for token in owner_prefix
                if token
                not in {
                    "C_LINKAGE",
                    "EXPORTED",
                    "consteval",
                    "constexpr",
                    "extern",
                    "inline",
                    "static",
                }
            ]
            if not owner_significant:
                continue
        parameter_words = [
            token
            for token, _, _ in tokens[opening + 1 : closing]
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token)
        ]
        if (
            not significant
            or "=" in prefix
            or (suffix and suffix[0] == ":")
            or (name[:1].isupper() and "auto" not in prefix)
            or "operator" in prefix
            or not parameter_declarations(
                [token for token, _, _ in tokens[opening + 1 : closing]]
            )
            or (
                "constexpr" in prefix
                and "auto" not in prefix
                and not parameter_words
            )
        ):
            continue
        if "auto" in prefix and "->" in suffix:
            continue
        errors.append(
            f"{path}:{line_at(source, tokens[start + 1][1])}: C++ function declarations use trailing return types"
        )
    return errors


def raw_allocation_offsets(source, code, allow_placement_new=False):
    tokens = [
        (match.group(0), match.start(), match.end())
        for match in TOKENS.finditer(code)
    ]
    offsets = []
    for index, (token, start, _) in enumerate(tokens):
        previous = tokens[index - 1][0] if index else ""
        following = tokens[index + 1][0] if index + 1 < len(tokens) else ""
        if token == "new":
            if previous == "operator":
                continue
            if (
                allow_placement_new
                and following == "("
                and index + 3 < len(tokens)
                and tokens[index + 2][0] == "address"
                and tokens[index + 3][0] == ")"
            ):
                continue
            offsets.append(start)
        elif token == "delete" and previous not in {"=", "operator"}:
            offsets.append(start)
        elif token in RAW_ALLOCATORS and following == "(":
            offsets.append(start)
    return offsets


def approved_file(path, root, project, approved):
    """Match an exceptional owner by SDK identity and exact source path."""
    relative = path.relative_to(root).as_posix()
    return (project, relative) in approved


def raw_allocation_errors(path, root, project, source, code):
    if approved_file(path, root, project, APPROVED_RAW_ALLOCATION_FILES):
        return []
    allow_placement_new = approved_file(
        path, root, project, APPROVED_PLACEMENT_NEW_FILES
    )
    return [
        f"{path}:{line_at(source, offset)}: raw allocation is restricted to "
        "exact project paths approved in Toolchain's source policy"
        for offset in raw_allocation_offsets(
            source, code, allow_placement_new=allow_placement_new
        )
    ]


def flexible_type_offsets(source, code):
    """Locate noncanonical numeric vocabulary."""
    tokens = [
        (match.group(0), match.start(), match.end())
        for match in TOKENS.finditer(code)
    ]
    offsets = []
    for index, (token, start, _) in enumerate(tokens):
        if token not in FLEXIBLE_TYPES:
            continue
        offsets.append((token, start))
    return offsets


def canonicalize_types(source, code):
    """Replace exact width compiler aliases with the project vocabulary."""
    tokens = list(TOKENS.finditer(code))
    replacements = []
    for index, match in enumerate(tokens):
        token = match.group(0)
        replacement = CANONICAL_TYPE_SUBSTITUTIONS.get(token)
        if (
            token == "int"
            and index + 2 < len(tokens)
            and tokens[index + 1].group(0) == "main"
            and tokens[index + 2].group(0) == "("
        ):
            replacement = "S32"
        if replacement is None:
            continue
        start = match.start()
        if (
            index >= 2
            and tokens[index - 2].group(0) == "std"
            and tokens[index - 1].group(0) == "::"
        ):
            start = tokens[index - 2].start()
        replacements.append(
            (start, match.end(), replacement)
        )
    for start, end, replacement in reversed(replacements):
        source = source[:start] + replacement + source[end:]
    return source


def flexible_type_errors(path, root, project, source, code):
    if approved_file(path, root, project, APPROVED_FLEXIBLE_TYPE_FILES):
        return []
    contract = (
        "uses the fixed width project vocabulary; select U*, S*, R*, Count, "
        "or CppSize according to the value contract"
    )
    return [
        f"{path}:{line_at(source, offset)}: noncanonical numeric type '{token}' {contract}"
        for token, offset in flexible_type_offsets(source, code)
    ]


def standard_integer_includes(source, code):
    matches = []
    for match in STANDARD_INTEGER_INCLUDE.finditer(source):
        start = source.rfind("\n", 0, match.start()) + 1
        end = source.find("\n", match.start())
        end = len(source) if end < 0 else end
        if directive(code[start:end]) == "include":
            matches.append(match)
    return matches


def standard_integer_errors(path, root, project, source, code):
    """Keep standard integer headers and macros outside canonical sources."""
    if approved_file(path, root, project, APPROVED_STANDARD_INTEGER_FILES):
        return []
    errors = [
        f"{path}:{line_at(source, match.start())}: Toolchain supplies the canonical integer vocabulary; remove this standard integer header"
        for match in standard_integer_includes(source, code)
    ]
    errors.extend(
        f"{path}:{line_at(source, match.start())}: standard integer macro '{match.group(0)}' requires a canonical project expression"
        for match in STANDARD_INTEGER_MACRO.finditer(code)
    )
    return errors


def remove_standard_integer_headers(source, code):
    matches = standard_integer_includes(source, code)
    for match in reversed(matches):
        source = source[:match.start()] + source[match.end():]
    return source


def directive(line):
    match = re.match(r"\s*#\s*([A-Za-z_][A-Za-z0-9_]*)", line)
    return match.group(1) if match else None


def logical_end(lines, index):
    while index + 1 < len(lines) and lines[index].rstrip().endswith("\\"):
        index += 1
    return index


def preprocessor_violations(source):
    """Locate missing paragraph boundaries around preprocessor regions."""
    lines = source.splitlines()
    violations = []
    for index, line in enumerate(lines):
        current = directive(line)
        if current in CONDITIONAL_DIRECTIVES:
            before = lines[index - 1] if index else ""
            end = logical_end(lines, index)
            after = lines[end + 1] if end + 1 < len(lines) else ""
            before_directive = directive(before)
            after_directive = directive(after)
            if (
                before.strip()
                and not before.lstrip().startswith(("//", "/*", "*"))
                and before_directive
                not in (CONDITIONAL_DIRECTIVES | PREPROCESSOR_CONTENT)
            ):
                violations.append(
                    (index, index, "conditional code has an empty line before its directive")
                )
            if (
                after.strip()
                and not after.lstrip().startswith("}")
                and after_directive
                not in (CONDITIONAL_DIRECTIVES | PREPROCESSOR_CONTENT)
            ):
                violations.append(
                    (index, end + 1, "conditional code has an empty line after its directive")
                )

    definitions = []
    index = 0
    while index < len(lines):
        if directive(lines[index]) == "define":
            end = logical_end(lines, index)
            if definitions and definitions[-1][1] + 1 == index:
                definitions[-1] = (definitions[-1][0], end)
            else:
                definitions.append((index, end))
            index = end + 1
        else:
            index += 1
    for start, end in definitions:
        before = lines[start - 1] if start else ""
        after = lines[end + 1] if end + 1 < len(lines) else ""
        if (
            before.strip()
            and not before.lstrip().startswith(("//", "/*", "*"))
            and directive(before) not in CONDITIONAL_DIRECTIVES
        ):
            violations.append(
                (
                    start,
                    start,
                    "definition groups have an empty line before their first directive",
                )
            )
        if after.strip() and directive(after) not in CONDITIONAL_DIRECTIVES:
            violations.append(
                (
                    end,
                    end + 1,
                    "definition groups have an empty line after their final directive",
                )
            )
    return violations


def preprocessor_errors(path, source):
    """Keep definitions and conditional code in explicit source regions."""
    return [
        f"{path}:{line + 1}: {message}"
        for line, _, message in preprocessor_violations(source)
    ]


def code_tokens(source, code):
    lines = source.splitlines(keepends=True)
    logical_lines = [value.rstrip("\n") for value in lines]
    masked = list(code)
    offset = 0
    for index, line in enumerate(lines):
        if directive(line):
            end = logical_end(logical_lines, index)
            length = sum(len(value) for value in lines[index:end + 1])
            for position in range(offset, offset + length):
                if masked[position] != "\n":
                    masked[position] = " "
        offset += len(line)
    return [
        (match.group(0), match.start(), match.end())
        for match in TOKENS.finditer("".join(masked))
    ]


def pairs(tokens, opening, closing):
    stack = []
    result = {}
    for index, (token, _, _) in enumerate(tokens):
        if token == opening:
            stack.append(index)
        elif token == closing and stack:
            start = stack.pop()
            result[start] = index
            result[index] = start
    return result


def first_word(tokens):
    for token, _, _ in tokens:
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token):
            return token
    return ""


def declaration(tokens):
    words = [token for token, _, _ in tokens]
    if not words or words[0] in STATEMENTS or words[0] in CONTROL:
        return False
    if words[0] in DECLARATIONS or words[0] == "decltype":
        return True

    index = 0
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", words[index]):
        return False
    index += 1
    while index + 1 < len(words) and words[index] == "::":
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", words[index + 1]):
            return False
        index += 2
    if index < len(words) and words[index] == "<":
        depth = 0
        while index < len(words):
            depth += words[index] == "<"
            depth -= words[index] == ">"
            index += 1
            if depth == 0:
                break
    while index < len(words) and words[index] in {
        "*",
        "&",
        "&&",
        "const",
        "volatile",
    }:
        index += 1
    return index < len(words) and (
        re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", words[index]) is not None
    )


def executable_scope(tokens, brace, parentheses):
    if brace == 0:
        return False
    previous = tokens[brace - 1][0]
    if previous in {"else", "try", "do"} or previous == "]":
        return True
    if previous == ")":
        opening = parentheses.get(brace - 1)
        return (
            opening is not None
            and (opening == 0 or tokens[opening - 1][0] != "requires")
        )
    return executable_signature(tokens, brace, parentheses)


def paragraph_violations(source, code):
    """Locate paragraphs that need a new lexical boundary.

    An empty line begins the next paragraph in the same lexical scope.
    """
    tokens = code_tokens(source, code)
    braces = pairs(tokens, "{", "}")
    parentheses = pairs(tokens, "(", ")")
    brackets = pairs(tokens, "[", "]")
    violations = []
    for opening in sorted(index for index in braces if index < braces[index]):
        closing = braces[opening]
        if not executable_scope(tokens, opening, parentheses):
            continue
        before = tokens[opening - 1][0] if opening else ""
        if before == ")":
            parenthesis = parentheses.get(opening - 1)
            if (
                parenthesis is not None
                and parenthesis
                and tokens[parenthesis - 1][0] == "switch"
            ):
                continue

        entities = []
        start = opening + 1
        index = start
        while index < closing:
            token = tokens[index][0]
            if token == "(":
                index = parentheses.get(index, index) + 1
                continue
            if token == "[":
                index = brackets.get(index, index) + 1
                continue
            if token == "{":
                end = braces.get(index)
                if end is None:
                    break
                prefix = tokens[start:index]
                if not prefix or first_word(prefix) in CONTROL:
                    head = first_word(prefix)
                    if (
                        head in {"else", "catch"}
                        and entities
                        and entities[-1][0] == "block"
                    ):
                        entities[-1] = (
                            entities[-1][0],
                            entities[-1][1],
                            tokens[end][2],
                            entities[-1][3],
                        )
                    else:
                        entities.append(
                            (
                                "block",
                                tokens[start][1] if prefix else tokens[index][1],
                                tokens[end][2],
                                head,
                            )
                        )
                    start = end + 1
                index = end + 1
                continue
            if token == ";":
                entity = tokens[start:index]
                if entity:
                    head = first_word(entity)
                    kind = (
                        "block"
                        if head in CONTROL
                        else "declaration"
                        if declaration(entity)
                        else "statement"
                    )
                    if head == "while" and entities and entities[-1][3] == "do":
                        entities[-1] = (
                            entities[-1][0],
                            entities[-1][1],
                            tokens[index][2],
                            entities[-1][3],
                        )
                    else:
                        entities.append(
                            (kind, entity[0][1], tokens[index][2], head)
                        )
                start = index + 1
            index += 1

        state = -1
        previous_end = tokens[opening][2]
        ranks = {"declaration": 0, "statement": 1, "block": 2}
        for kind, start_offset, end_offset, _ in entities:
            if re.search(r"\n[ \t]*\n", source[previous_end:start_offset]):
                state = -1
            rank = ranks[kind]
            if state == ranks["block"] or rank < state:
                violations.append(start_offset)
                state = rank
            else:
                state = max(state, rank)
            previous_end = end_offset
    return violations


def paragraph_errors(path, source, code):
    """Advance each paragraph from declarations to statements to one block."""
    return [
        f"{path}:{line_at(source, offset)}: lexical paragraphs progress through declarations, statements and one control block"
        for offset in paragraph_violations(source, code)
    ]


def multiline_brace_violations(source, code):
    """Separate a multiline braced entity from the source entity after it."""
    tokens = code_tokens(source, code)
    braces = pairs(tokens, "{", "}")
    parentheses = pairs(tokens, "(", ")")
    violations = []
    for opening in sorted(index for index in braces if index < braces[index]):
        closing = braces[opening]
        previous = tokens[opening - 1][0] if opening else ""
        preceding_parenthesis = parentheses.get(opening - 1)
        requires_expression = (
            previous == ")"
            and preceding_parenthesis is not None
            and preceding_parenthesis > 0
            and tokens[preceding_parenthesis - 1][0] == "requires"
        )
        if (
            requires_expression
            or source.find(
                "\n",
                tokens[opening][2],
                tokens[closing][1],
            )
            < 0
        ):
            continue

        closing_end = tokens[closing][2]
        current_end = source.find("\n", closing_end)
        if current_end < 0:
            continue
        suffix = code[closing_end:current_end].strip()
        if re.match(r"^(?:else|catch|while)\b", suffix):
            continue

        next_start = current_end + 1
        next_end = source.find("\n", next_start)
        next_end = len(source) if next_end < 0 else next_end
        following_source = source[next_start:next_end].strip()
        following_code = code[next_start:next_end].strip()
        if not following_source or re.match(
            r"^(?:}|else\b|catch\b|while\b)", following_code
        ):
            continue
        violations.append(next_start)
    return violations


def multiline_brace_errors(path, source, code):
    """Keep each multiline braced entity in its own source paragraph."""
    return [
        f"{path}:{line_at(source, offset)}: multiline braced entities end with an empty line before the next source entity"
        for offset in multiline_brace_violations(source, code)
    ]


def line_starts(source):
    starts = [0]
    for match in re.finditer("\n", source):
        starts.append(match.end())
    return starts


def canonicalize_source(path, root, project):
    """Apply mechanical vocabulary and include substitutions before Clang."""
    source = path.read_text()
    code, _ = lexical(source)
    canonical = canonicalize_types(source, code)
    if not approved_file(path, root, project, APPROVED_STANDARD_INTEGER_FILES):
        canonical_code, _ = lexical(canonical)
        canonical = remove_standard_integer_headers(canonical, canonical_code)
    if canonical != source:
        path.write_text(canonical)


def format_source(path):
    """Insert source-policy boundaries whose repair is purely lexical."""
    source = path.read_text()
    code, _ = lexical(source)
    starts = line_starts(source)
    insertions = {
        starts[line]
        for _, line, _ in preprocessor_violations(source)
        if line < len(starts)
    }
    insertions.update(
        source.rfind("\n", 0, offset) + 1
        for offset in paragraph_violations(source, code)
    )
    insertions.update(multiline_brace_violations(source, code))
    for offset in sorted(insertions, reverse=True):
        source = source[:offset] + "\n" + source[offset:]
    if insertions:
        path.write_text(source)


def source_errors(
    path,
    root,
    project,
    namespace_roots,
):
    source = path.read_text()
    code, _ = lexical(source)
    return (
        header_identity_errors(path, source, code)
        + namespace_errors(path, source, code)
        + qualified_namespace_errors(path, source, code, namespace_roots)
        + implementation_header_errors(path, root, source)
        + platform_header_errors(path, source)
        + system_include_errors(path, source, code)
        + declaration_errors(path, root, project, source, code)
        + trailing_return_errors(path, source, code)
        + raw_allocation_errors(path, root, project, source, code)
        + flexible_type_errors(path, root, project, source, code)
        + standard_integer_errors(path, root, project, source, code)
        + preprocessor_errors(path, source)
        + paragraph_errors(path, source, code)
        + multiline_brace_errors(path, source, code)
    )
