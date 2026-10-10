#!__PYTHON__
# Copyright (c) 2023-present Matt Kaes and contributors

"""Apply Toolchain's pinned C and C++ format and source policy."""

import argparse
import ast
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from format_policy import (
    canonicalize_source,
    contains_flexible_type,
    contains_raw_allocation,
    contains_standard_integer,
    format_source,
    source_errors,
)


CLANG_FORMAT = __CLANG_FORMAT__
CONFIGURATION = Path(__file__).with_name("__CONFIGURATION__")
DIRECTORIES = ("source", "validation", "examples", "tests", "benchmarks")
EXTENSIONS = {".c", ".cpp", ".h", ".hpp"}
POLICY_KEYS = {
    "flexible_type_files",
    "raw_allocation_files",
    "standard_integer_files",
}
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


def policy(root):
    """Load exact source-policy exceptions registered by the repository."""
    configuration = root / "toolchain.json"
    if not configuration.exists():
        return set(), set(), set()
    value = json.loads(configuration.read_text())
    if not isinstance(value, dict):
        raise ValueError("toolchain.json contains one policy object")
    unknown = set(value) - POLICY_KEYS
    if unknown:
        raise ValueError(
            "toolchain.json contains unknown policies: " + ", ".join(sorted(unknown))
        )
    policies = []
    for key, description, contains in [
        ("raw_allocation_files", "Raw allocation", contains_raw_allocation),
        ("flexible_type_files", "Flexible type", contains_flexible_type),
        (
            "standard_integer_files",
            "Standard integer",
            contains_standard_integer,
        ),
    ]:
        names = value.get(key, [])
        if not isinstance(names, list) or not all(
            isinstance(name, str) for name in names
        ):
            raise ValueError(f"toolchain.json {key} is a list of paths")
        if names != sorted(set(names)):
            raise ValueError(f"toolchain.json {key} is sorted and unique")
        files = set()
        for name in names:
            path = (root / name).resolve()
            if not path.is_relative_to(root):
                raise ValueError(f"{description} path leaves the workspace: {name}")
            if not path.is_file() or path.suffix not in EXTENSIONS:
                raise ValueError(f"{description} path is not a source file: {name}")
            if not contains(path):
                raise ValueError(f"{description} path contains no violation: {name}")
            files.add(name)
        policies.append(files)
    return tuple(policies)


def main():
    parser = argparse.ArgumentParser(
        description="Format exact files or check the complete source tree."
    )
    parser.add_argument("--all", action="store_true", help="format every source file")
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify formatting and source policy",
    )
    parser.add_argument("files", nargs="*", help="exact source files to format or check")
    arguments = parser.parse_args()

    workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace:
        parser.error("Bazel must supply BUILD_WORKSPACE_DIRECTORY")
    root = Path(workspace).resolve()
    try:
        local_project, dependency_projects = sdk_projects(root)
        expected_configuration = configuration(dependency_projects)
        namespace_roots = {
            namespace_name(project)
            for project in [local_project] + dependency_projects
        }
        (
            raw_allocation_files,
            flexible_type_files,
            standard_integer_files,
        ) = policy(root)
    except (json.JSONDecodeError, OSError, SyntaxError, ValueError) as error:
        parser.error(str(error))
    if arguments.all and (arguments.check or arguments.files):
        parser.error("--all selects the complete mutable source set")
    if arguments.all or (arguments.check and not arguments.files):
        files = discover(root)
    elif arguments.files:
        try:
            files = select(root, arguments.files)
        except ValueError as error:
            parser.error(str(error))
    else:
        parser.error("pass exact source files, --all, or --check")
    if not files:
        parser.error("the selected source set is empty")

    errors = []

    if not arguments.check:
        for path in files:
            canonicalize_source(path, root, standard_integer_files)

    with tempfile.TemporaryDirectory(prefix="toolchain-format-") as temporary:
        generated = Path(temporary) / ".clang-format"
        generated.write_text(expected_configuration)
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
        errors.extend(
            source_errors(
                path,
                root,
                raw_allocation_files,
                flexible_type_files,
                standard_integer_files,
                namespace_roots,
            )
        )
    if errors:
        print("\n".join(errors), file=sys.stderr)

    if formatted or errors:
        return 1
    action = "Checked" if arguments.check else "Formatted"
    print(f"{action} {len(files)} source files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
