# Copyright (c) 2023-present Matt Kaes and contributors

"""Consume Toolchain's built SDK fixtures through the real repository importer.

One immutable consumer workspace declares static, shared and deliberately
invalid SDKs together. Platform flags choose the compiler environment; targets
choose their SDK dependencies. The suite builds the consumer matrix and then
runs one source release through formatting, host tests, packaging and snapshot.
"""

from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

WINDOWS = os.name == "nt"
PLATFORM = "windows-x86_64-msvc" if WINDOWS else "linux-x86_64-v3"
CONSUMER_LIBRARY = "consumer_library.dll" if WINDOWS else "libconsumer_library.so"
EXECUTABLE = "consumer.exe" if WINDOWS else "consumer"


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checksum_bytes(content):
    return hashlib.sha256(content).hexdigest()


def substitute(template, values):
    for key, value in values.items():
        template = template.replace("{" + key + "}", value)
    return template


def verify_runtime(directory, archive_path, host):
    with zipfile.ZipFile(archive_path) as archive:
        archive.extractall(directory)
    metadata = json.loads((directory / "sdk.json").read_text())
    # A new process observes the extracted libraries and host platform runtime,
    # giving relocation an independent loader state after the build checks.
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("LD_", "RUNFILES_"))}
    command = [sys.executable, "-I", "-B", str(Path(__file__).resolve()), "--load",
               str(directory / metadata["library"])]
    missing_host = subprocess.run(command, cwd=directory, env=environment,
                                  capture_output=True, text=True)
    assert missing_host.returncode != 0, missing_host.stdout
    if not WINDOWS:
        assert host.name in missing_host.stderr, missing_host.stderr
    command.append(str(host))
    subprocess.run(command, cwd=directory, env=environment, check=True)
    for library in metadata["runtime"]:
        path = directory / library["library"]
        missing = path.with_suffix(path.suffix + ".missing")
        path.rename(missing)
        try:
            result = subprocess.run(command, cwd=directory, env=environment,
                                    capture_output=True, text=True)
            assert result.returncode != 0, f"Removed runtime dependency still loaded: {path.name}\n{result.stdout}"
            if not WINDOWS:
                assert path.name in result.stderr, result.stderr
        finally:
            missing.rename(path)
    print("Relocated shared SDK loaded; each missing dependency was rejected.", flush=True)
    return metadata


def verify_conflict(root, writer, first, second):
    manifest = root / "conflict.json"
    manifest.write_text(json.dumps({str(root / "conflict.zip"): [
        [str(first), "lib/library.so"], [str(second), "lib/library.so"],
    ]}))
    result = subprocess.run(
        [sys.executable, "-I", "-B", str(writer), str(manifest), str(root / "conflict.sha256")],
        capture_output=True, text=True,
    )
    assert result.returncode != 0 and "Conflicting archive entry: lib/library.so" in result.stderr, result.stderr
    print("Conflicting runtime libraries were rejected.", flush=True)


def verify_private_header_boundary(root, writer):
    boundary = root / "private-header"
    boundary.mkdir()
    public = boundary / "public.h"
    private = boundary / "detail.h"
    content = '// UTF-8 \u201cheader\u201d.\n'
    public.write_text(content, encoding="utf-8", newline="\n")
    private.write_text("#define TOOLCHAIN_PRIVATE_HEADER 1\n")
    manifest = boundary / "manifest.json"
    manifest.write_text(json.dumps({str(boundary / "headers.zip"): [
        [str(public), "include/project/public.h"],
        [str(private), "include/project/detail.h"],
    ]}))
    command = [sys.executable, "-I", "-B", str(writer), str(manifest), str(boundary / "sha256.txt")]
    subprocess.run(command, capture_output=True, text=True, check=True)
    with zipfile.ZipFile(boundary / "headers.zip") as archive:
        assert archive.read("include/project/public.h") == content.encode("utf-8")
        assert "include/project/detail.h" not in archive.namelist()
    public.write_text(content + '#include "detail.h"\n', encoding="utf-8", newline="\n")
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0, result.stdout
    assert (
        "Public header project/public.h includes private header project/detail.h"
        in result.stderr
    ), result.stderr
    print("UTF-8 header bytes preserved; public dependency on a private header rejected.", flush=True)


def conflicting_archives(directory, pins, version, variant, output, component=False):
    name = "tetro_toolchain-" + version + "-" + variant + ".zip"
    with zipfile.ZipFile(directory / name) as original:
        contents = {entry: original.read(entry) for entry in original.namelist()}
    metadata = json.loads(contents["sdk.json"])
    kind = "archives" if variant.endswith("-static") else "runtime"
    path = "lib/plugin.dll" if component else metadata[kind][0]["library"]
    contents[path] += b"different runtime fixture"
    metadata["sha256"][path] = checksum_bytes(contents[path])
    contents["sdk.json"] = json.dumps(metadata).encode()
    with zipfile.ZipFile(output / name, "w") as archive:
        for path, content in contents.items():
            archive.writestr(path, content)
    return dict(pins, **{variant: checksum(output / name)})


def verify_vscode(command, workspace):
    subprocess.run(command + ["run", "//:vscode"], cwd=workspace, check=True)
    generated = workspace / ".vscode"
    assert {path.name for path in generated.iterdir()} == {
        ".clang-format",
        "c_cpp_properties.json",
        "extensions.json",
        "launch.json",
        "settings.json",
        "tasks.json",
    }
    settings = json.loads((generated / "settings.json").read_text())
    assert settings["files.eol"] == "\n"
    assert settings["[c]"]["editor.defaultFormatter"] == "ms-vscode.cpptools"
    assert settings["[c]"]["editor.formatOnSave"] is True
    assert settings["[cpp]"]["editor.defaultFormatter"] == "ms-vscode.cpptools"
    assert settings["[cpp]"]["editor.formatOnSave"] is True
    assert settings["C_Cpp.formatting"] == "clangFormat"
    assert settings["C_Cpp.clang_format_fallbackStyle"] == "none"
    assert settings["C_Cpp.clang_format_style"] == (
        "file:${workspaceFolder}/.vscode/.clang-format"
    )
    formatter = Path(settings["C_Cpp.clang_format_path"])
    assert formatter.is_file()
    tasks = json.loads((generated / "tasks.json").read_text())["tasks"]
    build = next(task for task in tasks if task["label"] == "[Debug] Build All")
    subprocess.run(command + build["args"], cwd=workspace, check=True)
    for launch in json.loads((generated / "launch.json").read_text())["configurations"]:
        program = launch.get("windows", {}).get("program", launch["program"]) if WINDOWS else launch["program"]
        assert Path(program.replace("${workspaceFolder}", str(workspace))).is_file(), program
    result = subprocess.run(
        [
            str(formatter),
            "--style=file:" + str(generated / ".clang-format"),
            "--assume-filename=" + str(workspace / "source/style.cpp"),
        ],
        input="S32 main(){return 0;}\n",
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout == "S32 main() {\n  return 0;\n}\n", result.stdout
    print("VS Code uses the candidate Clang binary and generated style.", flush=True)


def verify_archives(checksum_manifest, dependency_manifest, version, mixed=False):
    directory = checksum_manifest.parent
    dependency_directory = dependency_manifest.parent
    pins = {}
    for project in ["tetro_toolchain", "toolchain_test"]:
        prefix = project + "-" + version + "-"
        pins[project] = {}
        # The checksum manifest is the exact archive inventory for this release.
        # Selecting its entries isolates the candidate from other build outputs.
        manifest = (dependency_directory if project == "tetro_toolchain" else directory) / (prefix + "sha256.txt")
        for entry in manifest.read_text().splitlines():
            digest, name = entry.split(maxsplit=1)
            assert name.startswith(prefix) and name.endswith(".zip"), name
            path = manifest.parent / name
            assert checksum(path) == digest, path
            key = path.name.removeprefix(prefix).removesuffix(".zip")
            assert key != "source", name
            pins[project][key] = digest
            with zipfile.ZipFile(path) as archive:
                assert "LICENSE" in archive.namelist(), archive.namelist()
                if key == "headers":
                    for name in [
                        "toolchain/export.h",
                        "toolchain/compile/allocation.hpp",
                        "toolchain/compile/source_location.hpp",
                        "toolchain/memory/lifetime.hpp",
                        "toolchain/toolchain.h",
                        "toolchain/toolchain.hpp",
                    ]:
                        assert "include/" + name in archive.namelist()
                    if project == "toolchain_test":
                        assert "include/validation/data/sdk/public.h" in archive.namelist()
                        assert "include/validation/data/sdk/private/library_detail.h" not in archive.namelist()
                        for name in ["project.h", "runtime.h", "project_detail.h"]:
                            assert not any(path.endswith("/" + name) for path in archive.namelist()), archive.namelist()
                    continue
                metadata = json.loads(archive.read("sdk.json"))
                assert metadata["linkage"] == key.rsplit("-", 1)[1]
                assert metadata["project"] == project.upper()
                assert metadata["library"] in archive.namelist()
                runtime = metadata["runtime"]
                shared_dependencies = key.endswith("-shared") != (mixed and project == "toolchain_test")
                expected_runtime = (2 if project == "toolchain_test" else 1) if shared_dependencies else 0
                if key.startswith("windows-"):
                    expected_runtime += 1
                    assert {"library": "lib/plugin.dll", "interface": None} in runtime
                assert len(runtime) == expected_runtime, metadata
                expected_archives = (2 if project == "toolchain_test" else 1) if key.endswith("-static") and not shared_dependencies else 0
                assert len(metadata["archives"]) == expected_archives, metadata
                system = metadata["system"]
                assert len(system) == (0 if key.startswith("wasm32-") else 1), metadata
                for library in system:
                    assert library["interface"].startswith("link/")
                    assert library["interface"] in archive.namelist()
                    if key.startswith("linux-") and key.endswith("-static") and not shared_dependencies:
                        assert library["linkopts"] == ["-Wl,--undefined=toolchain_host_entry"], library
                assert "lib/system_host.dll" not in archive.namelist()
                assert "lib/libsystem_host.so.1" not in archive.namelist()
                assert len(archive.namelist()) == len(set(archive.namelist()))
                for library in runtime:
                    assert library["library"] in archive.namelist()
                    if library["library"] == "lib/plugin.dll":
                        assert library["interface"] is None, library
                        assert "lib/plugin.lib" not in archive.namelist()
                    elif key.startswith("windows-"):
                        assert library["interface"] in archive.namelist()
                for library in metadata["archives"]:
                    assert library["library"] in archive.namelist()
                    assert library["library"].endswith("_static.lib" if key.startswith("windows-") else ".a")
                if project == "toolchain_test":
                    assert "TOOLCHAIN_TEST_VALUE=21" in metadata["defines"]
                    assert "TOOLCHAIN_TEST_PRIVATE=1" not in metadata["defines"]
                    assert "TOOLCHAIN_TEST_EXPORT=1" not in metadata["defines"]
                    assert "TOOLCHAIN_TEST_PUBLIC=1" in metadata["defines"]
                    for define in ["TOOLCHAIN_PROJECT_VALUE=1", "TETRO_TOOLCHAIN_STATIC=1", "TOOLCHAIN_PRIVATE_STATIC=1"]:
                        assert define not in metadata["defines"], metadata
                    expected_flags = ["-Wl,--wrap=toolchain_link_probe"] if key.startswith("linux-") else []
                    assert metadata["linkopts"] == expected_flags
                    components = metadata["components"]
                    assert sorted(components) == ["api", "public"], components
                    assert components["api"]["dependencies"] == ["public"], components
                    assert components["public"]["dependencies"] == [], components
                    assert "validation/data/sdk/library.h" in components["api"]["headers"], components
                    assert "validation/data/sdk/private/library_detail.h" not in components["api"]["headers"], components
                    assert "validation/data/sdk/public.h" not in components["api"]["headers"], components
                    assert "validation/data/sdk/public.h" in components["public"]["headers"], components
                if metadata["interface"]:
                    assert metadata["interface"] in archive.namelist()
                if key == "windows-x86_64-msvc-static":
                    assert metadata["library"].endswith("_static.lib")

    return pins


def verify_repack(directory, output, version, linkage):
    for platform in ["linux-x86_64-v3", "windows-x86_64-msvc", "wasm32-emscripten"]:
        name = "toolchain_test-" + version + "-" + platform + "-" + linkage + ".zip"
        with zipfile.ZipFile(directory / name) as before, zipfile.ZipFile(output / name) as after:
            original = json.loads(before.read("sdk.json"))
            repacked = json.loads(after.read("sdk.json"))
            assert original["library"] == repacked["library"]
            assert before.read(original["library"]) == after.read(repacked["library"])
            for field in ["components", "runtime"]:
                assert original[field] == repacked[field], (field, original[field], repacked[field])
            assert [item["interface"] for item in original["system"]] == [item["interface"] for item in repacked["system"]]
            for first, second in zip(original["system"], repacked["system"]):
                remaining = iter(second["linkopts"])
                assert all(flag in remaining for flag in first["linkopts"])
            assert len(after.namelist()) == len(set(after.namelist()))
            for library in repacked["runtime"]:
                assert before.read(library["library"]) == after.read(library["library"])
            assert sorted(checksum_bytes(before.read(item["library"])) for item in original["archives"]) == sorted(checksum_bytes(after.read(item["library"])) for item in repacked["archives"])


def verify_release(command, workspace, version):
    subprocess.run(command + ["run", "//:sdk"], cwd=workspace, check=True)
    snapshot = workspace / (".bin/release/consumer-" + version + "-source.tar.gz")
    assert snapshot.exists()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=workspace, text=True)
    assert snapshot.with_name(snapshot.name + ".commit").read_text() == commit
    assert snapshot.with_name(snapshot.name + ".sha256").read_text() == checksum(snapshot) + "  " + snapshot.name + "\n"
    with tarfile.open(snapshot, "r:gz") as archive:
        assert archive.extractfile("MODULE.bazel").read() == (workspace / "MODULE.bazel").read_bytes()
    assert not (workspace / ".clang-format").exists()
    print("Source release passed formatting, host tests, packaging and its source snapshot.", flush=True)


def verify(toolchain, matching, mixed, host, objdump, case):
    version = toolchain.name.removeprefix("tetro_toolchain-").removesuffix("-source.tar.gz")
    repository = Path.cwd()
    sources = repository / "validation/data/sdk"
    with tarfile.open(toolchain, "r:gz") as archive:
        packaged_sources = set(archive.getnames())
        project_files = {name: archive.extractfile(name).read() for name in [".bazelrc", "LICENSE"]}
    for path in ["source/bazel/rules/.clang-format", "source/toolchain/validation/move_only.hpp", "source/toolchain/validation/tracked_value.hpp"]:
        assert path in packaged_sources, path
    assert ".clang-format" not in packaged_sources
    pins = verify_archives(matching, matching, version)
    mixed_pins = verify_archives(mixed, matching, version, mixed=True)
    families = ["matching", "mixed"] if case == "all" else [case]
    directories = {"matching": matching.parent, "mixed": mixed.parent}
    cases = [family + "_" + linkage for family in families for linkage in ["static", "shared"]]

    with tempfile.TemporaryDirectory(prefix="toolchain-sdk-test-") as temporary, ExitStack() as cleanup:
        root = Path(temporary)
        conflicts = root / "conflicts"
        conflicts.mkdir()
        values = {
            "version": version,
            "toolchain_sha256": checksum(toolchain),
            "dependency_archives": repr(pins["tetro_toolchain"]),
            "matching_archives": repr(pins["toolchain_test"]),
            "mixed_archives": repr(mixed_pins["toolchain_test"]),
            "bad_static_archives": repr(conflicting_archives(matching.parent, pins["tetro_toolchain"], version, "linux-x86_64-v3-static", conflicts)),
            "bad_shared_archives": repr(conflicting_archives(matching.parent, pins["tetro_toolchain"], version, "linux-x86_64-v3-shared", conflicts)),
            "bad_component_archives": repr(conflicting_archives(matching.parent, pins["tetro_toolchain"], version, "windows-x86_64-msvc-static", conflicts, component=True)),
            "missing_archives": repr({key: digest for key, digest in pins["toolchain_test"].items() if key == "headers" or key.endswith("-static")}),
        }
        workspace = root / "consumer"
        workspace.mkdir()
        command = ["bazel", "--output_base=" + str(root / "bazel")]
        cleanup.callback(subprocess.run, command + ["shutdown"], cwd=workspace, check=True)
        for name, content in project_files.items():
            if name == ".bazelrc":
                content = b"\n".join(line for line in content.splitlines() if not line.startswith(b"build")) + b"\n"
                content += b"build -c opt --strip=always --platforms=@bazel_tools//tools:host_platform\nbuild --spawn_strategy=local\n"
                for directory in [conflicts, matching.parent, mixed.parent, toolchain.parent]:
                    content += ("\ncommon --distdir=" + json.dumps(directory.as_posix()) + "\n").encode()
            (workspace / name).write_bytes(content)
        module = substitute((sources / "module.tpl").read_text(), values)
        (workspace / "MODULE.bazel").write_text(module, encoding="utf-8", newline="\n")
        for output, source in {
            "BUILD": sources / "consumer.build",
            "source/BUILD": sources / "consumer.source.build",
            "source/consumer/application/value.c": sources / "release.c",
            "source/consumer/application/value.h": sources / "release.h",
            "validation/tests/web.cpp": sources / "web_test.cpp.tpl",
            "validation/benchmarks/web.cpp": sources / "web_benchmark.cpp",
            "consumer.c": repository / "validation/integration/sdk.c",
            "dependency.c": sources / "dependency.c",
            "library.c": sources / "consumer.c",
        }.items():
            path = workspace / output
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, path)
        (workspace / ".gitignore").write_text(".bin/\n.bazelrc.local\nMODULE.bazel.lock\n.vscode/\n")
        for arguments in [
            ["init", "--quiet"],
            ["add", "."],
            ["-c", "user.name=Toolchain Validation", "-c", "user.email=validation@tetrodotoxin.dev", "commit", "--quiet", "-m", "SDK release fixture"],
        ]:
            subprocess.run(["git", *arguments], cwd=workspace, check=True)

        host_directory = root / "host-runtime"
        host_directory.mkdir()
        shutil.copyfile(host, host_directory / host.name)
        host = host_directory / host.name
        variable = "PATH" if WINDOWS else "LD_LIBRARY_PATH"
        runtime_environment = dict(os.environ)
        runtime_environment[variable] = str(host.parent) + os.pathsep + runtime_environment.get(variable, "")

        targets = ["//:" + name + "/" + target for name in cases for target in ["consumer", "component", "alternate/consumer", "consumer_library_shared"]]
        standalone = ["//:" + family + "/standalone" for family in families]
        subprocess.run(command + ["build", *targets, *standalone], cwd=workspace, check=True)
        output = workspace / ".bin/bin"
        for name in cases:
            for executable in [EXECUTABLE, "component.exe" if WINDOWS else "component", "alternate/" + EXECUTABLE]:
                subprocess.run([str(output / name / executable)], cwd=workspace, env=runtime_environment, check=True)
            subprocess.run([sys.executable, "-I", "-B", str(Path(__file__).resolve()), "--load-consumer", str(output / name / CONSUMER_LIBRARY), str(host)],
                           env=runtime_environment, check=True)
            if WINDOWS:
                for directory in [output / name, output / name / "alternate"]:
                    assert (directory / "plugin.dll").is_file()
            if name.endswith("_static"):
                dynamic = subprocess.run([str(objdump), "-p", str(output / name / EXECUTABLE)], capture_output=True, text=True, check=True).stdout
                dependency_name = "dependency_shared.dll" if WINDOWS else "libdependency_shared.so"
                assert (dependency_name in dynamic) == name.startswith("mixed"), dynamic
                if name.startswith("matching"):
                    assert ("runtime.dll" if WINDOWS else "libruntime.so") not in dynamic, dynamic
        for family in families:
            subprocess.run([str(output / family / ("standalone.exe" if WINDOWS else "standalone"))], cwd=workspace, env=runtime_environment, check=True)
        print("Host SDK consumers and bundled static dependencies passed: " + ", ".join(cases), flush=True)

        for name in cases:
            subprocess.run(command + ["build", "//:_repack_archives", "--define=sdk_case=" + name], cwd=workspace, check=True)
            family, linkage = name.split("_")
            verify_repack(directories[family], output, version, linkage)
            if linkage == "shared":
                repacked = output / ("toolchain_test-" + version + "-" + PLATFORM + "-shared.zip")
                relocated = root / ("relocated-" + family)
                metadata = verify_runtime(relocated, repacked, host)
                if metadata["runtime"]:
                    verify_conflict(root, repository / "source/bazel/release/package.py",
                                    relocated / metadata["library"], relocated / metadata["runtime"][0]["library"])
        print("SDK components, dependencies and runtime payloads survived repackaging.", flush=True)

        for platform in ["linux_x86_64", "windows_x64", "wasm32"]:
            if platform == ("windows_x64" if WINDOWS else "linux_x86_64"):
                continue
            subprocess.run(command + ["build", *targets, "--platforms=@tetro_toolchain//:" + platform], cwd=workspace, check=True)
            if platform == "windows_x64":
                for name in cases:
                    for directory in [output / name, output / name / "alternate"]:
                        assert (directory / "plugin.dll").is_file()
            print("SDK consumers built for " + platform, flush=True)

        negative_targets = []
        diagnostics = []
        if "matching" in families:
            negative_targets.append("//:conflict_archive")
            diagnostics.append("Bundled archive disagrees with a declared SDK dependency")
        if "mixed" in families:
            negative_targets.append("//:conflict_runtime")
            diagnostics.append("Bundled runtime disagrees with a declared SDK dependency")
        failures = [("linux_x86_64", negative_targets, diagnostics)]
        if "mixed" in families:
            failures.append(("windows_x64", ["//:conflict_component"], ["Conflicting SDK runtime contents or link requirements for plugin.dll"]))
        if "matching" in families:
            failures.append(("windows_x64" if WINDOWS else "linux_x86_64", ["//:missing_variant"], ["No platform archives supply the requested shared linkage"]))
        for platform, invalid, diagnostics in failures:
            result = subprocess.run(command + ["build", *invalid, "--keep_going", "--platforms=@tetro_toolchain//:" + platform],
                                    cwd=workspace, capture_output=True, text=True)
            assert result.returncode != 0, result.stdout
            assert all(message in result.stderr for message in diagnostics), result.stderr
        print("Conflicting SDK dependencies and missing variants were rejected.", flush=True)

        if "matching" in families:
            selected = subprocess.check_output(command + ["query", "labels(actual, //:_validation_static)"], cwd=workspace, text=True).strip()
            assert selected == "//source:consumer", selected
            subprocess.run(command + ["run", "//:tests_web"], cwd=workspace, check=True)
            verify_release(command, workspace, version)
            verify_vscode(command, workspace)
        assert (workspace / "MODULE.bazel").read_text(encoding="utf-8") == module
        assert not list(output.glob("*-source.zip"))


if __name__ == "__main__":
    if sys.argv[1] in ["--load", "--load-consumer"]:
        import ctypes
        if WINDOWS:
            os.environ["PATH"] = str(Path(sys.argv[2]).parent) + os.pathsep + os.environ.get("PATH", "")
        if len(sys.argv) > 3:
            ctypes.CDLL(sys.argv[3], mode=ctypes.RTLD_GLOBAL)
        library = ctypes.CDLL(sys.argv[2])
        if sys.argv[1] == "--load-consumer":
            assert library.toolchain_consumer_entry(21) == 42
        else:
            assert library.toolchain_c_entry(20) == 21
            assert library.toolchain_cpp_entry(21) == 42
    else:
        toolchain, matching, mixed, host, objdump = [Path(argument).resolve() for argument in sys.argv[1:-1]]
        case = sys.argv[-1]
        assert case in ["all", "matching", "mixed"], case
        repository = Path.cwd()
        with tempfile.TemporaryDirectory(prefix="toolchain-private-header-") as temporary:
            verify_private_header_boundary(Path(temporary), repository / "source/bazel/release/package.py")
        os.environ.pop("BUILD_WORKSPACE_DIRECTORY", None)
        os.environ.pop("BUILD_WORKING_DIRECTORY", None)
        os.environ["HOME"] = str(Path.home())
        os.environ.pop("TEST_TMPDIR", None)
        for key in list(os.environ):
            if key.startswith("RUNFILES_"):
                del os.environ[key]
        verify(toolchain, matching, mixed, host, objdump, case)
