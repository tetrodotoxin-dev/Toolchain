#!__PYTHON__
# Copyright (c) 2023-present Matt Kaes and contributors

"""Apply Toolchain's pinned C and C++ format and source policy."""

import argparse
import ast
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from comment_quality import classify_comments, diagnostic, summary
from format_policy import (
    canonicalize_source,
    duplicate_implementation_type_errors,
    format_source,
    lexical,
    source_errors,
)


CLANG_FORMAT = __CLANG_FORMAT__
CONFIGURATION = Path(__file__).with_name("__CONFIGURATION__")
DIRECTORIES = ("source", "validation", "examples", "tests", "benchmarks")
EXTENSIONS = {".c", ".cpp", ".h", ".hpp"}
BUCKETS_BEGIN = "# SDK dependency include buckets begin."
BUCKETS_END = "# SDK dependency include buckets end."


def keyword(call, name):
    for value in call.keywords:
        if value.arg == name and isinstance(value.value, ast.Constant):
            return value.value.value
    return None


def sdk_projects(root):
    """Read SDK dependency order and local identity from MODULE.bazel."""
    module = root / "MODULE.bazel"
    tree = ast.parse(module.read_text(), filename=str(module))
    extension_names = set()
    local = None
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            if node.func.id == "module":
                local = keyword(node, "name")
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        value = node.value
        if (
            isinstance(target, ast.Name)
            and isinstance(value, ast.Call)
            and isinstance(value.func, ast.Name)
            and value.func.id == "use_extension"
            and len(value.args) >= 2
            and isinstance(value.args[0], ast.Constant)
            and isinstance(value.args[1], ast.Constant)
            and isinstance(value.args[0].value, str)
            and isinstance(value.args[1].value, str)
            and value.args[0].value.endswith(":sdk.bzl")
            and value.args[1].value == "dependencies"
        ):
            extension_names.add(target.id)
    if not isinstance(local, str) or not local:
        raise ValueError("MODULE.bazel must declare module(name=...)")

    local = (
        "toolchain"
        if local == "tetro_toolchain"
        else local.lower().replace("-", "_").replace(".", "_")
    )

    # Toolchain supplies the common export and validation headers to every
    # dependent SDK. Its own repository reaches those headers through the local
    # bucket. Each release project then names its published include root.
    projects = [] if local == "toolchain" else ["toolchain"]
    releases = []
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "release"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in extension_names
        ):
            releases.append(node)
    for release in sorted(releases, key=lambda node: (node.lineno, node.col_offset)):
        project = keyword(release, "project")
        if not isinstance(project, str) or not project:
            raise ValueError(
                f"MODULE.bazel:{release.lineno}: SDK releases declare project identity"
            )
        project = project.lower().replace("-", "_").replace(".", "_")
        if project != local and project not in projects:
            projects.append(project)
    return local, projects


def namespace_name(project):
    """Convert an SDK project identity to its C++ namespace root."""
    return "".join(word[:1].upper() + word[1:] for word in project.split("_"))


def configuration(projects):
    """Generate clang-format include buckets from the repository module."""
    source = CONFIGURATION.read_text()
    begin = source.index(BUCKETS_BEGIN)
    end = source.index(BUCKETS_END, begin) + len(BUCKETS_END)
    categories = [
        BUCKETS_BEGIN,
        "IncludeCategories:",
        "  - Regex:      '^<.*\\.h>'",
        "    Priority:   1",
    ]
    priority = 2
    for project in projects:
        categories.extend([
            "  - Regex:      '^\"" + re.escape(project) + "/'",
            "    Priority:   " + str(priority),
        ])
        priority += 1
    categories.extend([
        "  - Regex:      '^\".*\"'",
        "    Priority:   " + str(priority),
        "  - Regex:      '.*'",
        "    Priority:   " + str(priority + 1),
        BUCKETS_END,
    ])
    return source[:begin] + "\n".join(categories) + source[end:]


def discover(root):
    files = []
    for directory in DIRECTORIES:
        owner = root / directory
        if owner.is_dir():
            files.extend(
                path
                for path in owner.rglob("*")
                if path.is_file() and path.suffix in EXTENSIONS
            )
    return sorted(files)


def select(root, names):
    files = []
    for name in names:
        path = (root / name).resolve()
        if not path.is_relative_to(root):
            raise ValueError(f"Source path leaves the workspace: {name}")
        if not path.is_file() or path.suffix not in EXTENSIONS:
            raise ValueError(f"Expected one C or C++ source file: {name}")
        files.append(path)
    return sorted(set(files))


def main():
    parser = argparse.ArgumentParser(
        description="Format the complete source tree or selected exact files."
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="explicitly format every source file",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify formatting and source policy",
    )
    parser.add_argument(
        "--export-configuration",
        metavar="PATH",
        help="write the generated clang-format configuration inside the workspace",
    )
    parser.add_argument("files", nargs="*", help="exact source files to format or check")
    arguments = parser.parse_args()

    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace:
        parser.error("Bazel must supply BUILD_WORKSPACE_DIRECTORY")
    root = Path(workspace).resolve()
    try:
        if (root / "toolchain.json").exists():
            raise ValueError(
                "Toolchain source policy owns exceptional project paths. "
                "Remove toolchain.json and register approved paths in Toolchain"
            )
        local_project, dependency_projects = sdk_projects(root)
        expected_configuration = configuration(dependency_projects)
        namespace_roots = {
            namespace_name(project)
            for project in [local_project] + dependency_projects
        }
    except (OSError, SyntaxError, ValueError) as error:
        parser.error(str(error))
    if arguments.export_configuration:
        if arguments.all or arguments.check or arguments.files:
            parser.error("--export-configuration selects one generated output")
        destination = (root / arguments.export_configuration).resolve()
        if not destination.is_relative_to(root):
            parser.error("Generated configuration path leaves the workspace")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(expected_configuration, newline="\n")
        print(
            "Generated format configuration at "
            + destination.relative_to(root).as_posix()
            + "."
        )
        return 0
    if arguments.all and (arguments.check or arguments.files):
        parser.error("--all selects the complete mutable source set")
    if arguments.all or not arguments.files:
        files = discover(root)
    else:
        try:
            files = select(root, arguments.files)
        except ValueError as error:
            parser.error(str(error))
    if not files:
        parser.error("the selected source set is empty")

    errors = []
    warnings = []
    comment_verdicts = []
    parsed = {}

    if not arguments.check:
        for path in files:
            canonicalize_source(path, root, local_project)

    with tempfile.TemporaryDirectory(prefix="toolchain-format-") as temporary:
        generated = Path(temporary) / ".clang-format"
        generated.write_text(expected_configuration, newline="\n")
        command = [
            CLANG_FORMAT,
            "--Werror",
            "--fail-on-incomplete-format",
            "--fallback-style=none",
            "--style=file:" + str(generated),
        ]
        command.extend(["--dry-run"] if arguments.check else ["-i"])
        command.extend(str(path) for path in files)
        formatted = subprocess.run(command).returncode

    if not arguments.check:
        for path in files:
            format_source(path)

    for path in files:
        source = path.read_text()
        code, comments = lexical(source)
        parsed[path] = (source, code)
        errors.extend(
            source_errors(
                path,
                root,
                local_project,
                namespace_roots,
                source,
                code,
            )
        )
        verdicts = classify_comments(path, source, comments, code)
        comment_verdicts.extend(verdicts)
        for verdict in verdicts:
            if verdict.decision == "Reject":
                errors.append(diagnostic(verdict))
            elif verdict.decision == "Warn":
                warnings.append(diagnostic(verdict))
    errors.extend(
        duplicate_implementation_type_errors(
            [path for path in discover(root) if path.suffix == ".cpp"],
            files,
            parsed,
        )
    )
    report = [summary(comment_verdicts)] + warnings + errors
    stream = sys.stderr if warnings or errors else sys.stdout
    print("\n".join(report), file=stream, flush=True)

    if formatted or errors:
        return 1
    action = "Checked" if arguments.check else "Formatted"
    print(f"{action} {len(files)} source files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
