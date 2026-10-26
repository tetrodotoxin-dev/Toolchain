# Copyright (c) 2023-present Matt Kaes and contributors

"""Consume Toolchain's built SDK fixtures through the real repository importer.

The //validation/integration:sdk test supplies the candidate source and
fixture archives through Bazel runfiles. Bazel's distdir serves those exact
files under their release URLs, testing packaging before publication while the
consumer retains fixed dependency pins. The validator builds Linux, Windows
and WebAssembly consumers. Windows acquisition uses the pinned packages by
default and honors an explicitly selected installed SDK.
"""

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
    command = [sys.executable, str(Path(__file__).resolve()), "--load",
               str(directory / metadata["library"])]
    missing_host = subprocess.run(command, cwd=directory, env=environment,
                                  capture_output=True, text=True)
    assert missing_host.returncode != 0 and host.name in missing_host.stderr, missing_host.stderr
    command.append(str(host))
    subprocess.run(command, cwd=directory, env=environment, check=True)
    for library in metadata["runtime"]:
        path = directory / library["library"]
        missing = path.with_suffix(path.suffix + ".missing")
        path.rename(missing)
        try:
            result = subprocess.run(command, cwd=directory, env=environment,
                                    capture_output=True, text=True)
            assert result.returncode != 0 and path.name in result.stderr, result.stderr
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
        [sys.executable, str(writer), str(manifest), str(root / "conflict.sha256")],
        capture_output=True, text=True,
    )
    assert result.returncode != 0 and "Conflicting archive entry: lib/library.so" in result.stderr, result.stderr
    print("Conflicting runtime libraries were rejected.", flush=True)


def verify_private_header_boundary(root, writer):
    boundary = root / "private-header"
    boundary.mkdir()
    public = boundary / "public.h"
    private = boundary / "detail.h"
    public.write_text('#include "detail.h"\n')
    private.write_text("#define TOOLCHAIN_PRIVATE_HEADER 1\n")
    manifest = boundary / "manifest.json"
    manifest.write_text(json.dumps({str(boundary / "headers.zip"): [
        [str(public), "include/project/public.h"],
        [str(private), "include/project/detail.h"],
    ]}))
    result = subprocess.run(
        [sys.executable, str(writer), str(manifest), str(boundary / "sha256.txt")],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0, result.stdout
    assert (
        "Public header project/public.h includes private header project/detail.h"
        in result.stderr
    ), result.stderr
    print("Public dependency on a private header was rejected.", flush=True)


def verify_dependency_conflict(root, workspace, toolchain, directory, dependency_directory, sources, values, pins, component=False):
    altered = root / ("conflicting-component" if component else "conflicting")
    altered.mkdir()
    platform = "windows-x86_64-msvc" if component else "linux-x86_64-v3"
    variant = platform + "-" + values["dependency_linkage"]
    name = "tetro_toolchain-" + values["version"] + "-" + variant + ".zip"
    with zipfile.ZipFile(dependency_directory / name) as original:
        contents = {entry: original.read(entry) for entry in original.namelist()}
    metadata = json.loads(contents["sdk.json"])
    kind = "archives" if values["dependency_linkage"] == "static" else "runtime"
    path = "lib/plugin.dll" if component else metadata[kind][0]["library"]
    contents[path] += b"different runtime fixture"
    metadata["sha256"][path] = hashlib.sha256(contents[path]).hexdigest()
    contents["sdk.json"] = json.dumps(metadata).encode()
    with zipfile.ZipFile(altered / name, "w") as archive:
        for path, content in contents.items():
            archive.writestr(path, content)
    conflict = dict(values)
    conflict["dependency_archives"] = repr(dict(pins, **{
        variant: checksum(altered / name),
    }))
    conflict["dependency_pin"] = substitute((sources / "dependency.tpl").read_text(), conflict)
    (workspace / "MODULE.bazel").write_text(substitute((sources / "MODULE.tpl").read_text(), conflict))
    result = subprocess.run([
        "bazel", "--batch", "--output_base=" + str(root / "bazel"),
        "build", "//:component" if component else "//:consumer", "--distdir=" + str(altered),
        "--platforms=@tetro_toolchain//:" + ("windows_x64" if component else "linux_x86_64"),
        "--distdir=" + str(toolchain.parent), "--distdir=" + str(directory),
        "--distdir=" + str(dependency_directory),
    ], cwd=workspace, capture_output=True, text=True)
    diagnostic = ("Bundled archive" if kind == "archives" else "Bundled runtime") + " disagrees with a declared SDK dependency"
    if component:
        diagnostic = "Conflicting SDK runtime contents or link requirements for plugin.dll"
    assert result.returncode != 0 and diagnostic in result.stderr, result.stderr
    print("Incompatible SDK dependency was rejected during import.", flush=True)


def verify_vscode(root, workspace, toolchain, directory):
    subprocess.run([
        "bazel", "--batch", "--output_base=" + str(root / "bazel"),
        "run", "//:vscode", "--distdir=" + str(toolchain.parent),
        "--distdir=" + str(directory),
    ], cwd=workspace, check=True)
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


def verify_missing_variant(root, workspace, toolchain, directory, sources, values, pins):
    missing = dict(values, library_archives=repr({
        key: digest for key, digest in pins.items()
        if key == "headers" or key.endswith("-static")
    }))
    (workspace / "MODULE.bazel").write_text(substitute((sources / "MODULE.tpl").read_text(), missing))
    result = subprocess.run([
        "bazel", "--batch", "--output_base=" + str(root / "bazel"),
        "build", "//:consumer", "--distdir=" + str(toolchain.parent),
        "--distdir=" + str(directory),
    ], cwd=workspace, capture_output=True, text=True)
    assert result.returncode != 0 and "No platform archives supply the requested shared linkage" in result.stderr, result.stderr
    print("Missing linkage failed without selecting another variant.", flush=True)


def verify(toolchain, checksum_manifest, dependency_manifest, host, mixed=False):
    toolchain = Path(toolchain).resolve()
    directory = Path(checksum_manifest).resolve().parent
    dependency_directory = Path(dependency_manifest).resolve().parent
    version = toolchain.name.removeprefix("tetro_toolchain-").removesuffix("-source.tar.gz")
    repository = Path(__file__).resolve().parents[2]
    sources = repository / "validation/data/sdk"
    with tarfile.open(toolchain, "r:gz") as archive:
        packaged_sources = set(archive.getnames())
        project_files = {
            name: archive.extractfile(name).read()
            for name in [".bazelrc", ".bazelversion", "LICENSE"]
        }
    assert "source/bazel/rules/.clang-format.tpl" in packaged_sources
    assert "source/toolchain/validation/move_only.hpp" in packaged_sources
    assert "source/toolchain/validation/tracked_value.hpp" in packaged_sources
    assert ".clang-format" not in packaged_sources

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

    # The temporary workspace owns consumer configuration and one test source.
    # Candidate archives supply every SDK header, library and Bazel rule.
    with tempfile.TemporaryDirectory(prefix="toolchain-sdk-test-") as temporary:
        root = Path(temporary)
        workspace = root / "consumer"
        workspace.mkdir()
        for name, content in project_files.items():
            (workspace / name).write_bytes(content)
        # Both fixture families share the separately packaged dependency SDK.
        # These are pinned local test artifacts served by Bazel's distdir.
        with (workspace / ".bazelrc").open("a") as options:
            options.write("\ncommon --distdir=" + str(dependency_directory) + "\n")
            options.write("test --test_env=LD_LIBRARY_PATH=" + str(host.parent) + "\n")
        (workspace / "source").mkdir()
        shutil.copyfile(sources / "source.tpl", workspace / "source/BUILD.bazel")
        shutil.copyfile(sources / "style.cpp", workspace / "source/style.cpp")
        (workspace / "multiple").mkdir()
        shutil.copyfile(sources / "multiple.tpl", workspace / "multiple/BUILD")
        (workspace / "validation/tests").mkdir(parents=True)
        (workspace / "validation/benchmarks").mkdir(parents=True)
        shutil.copyfile(sources / "web_test.cpp", workspace / "validation/tests/web.cpp")
        shutil.copyfile(sources / "web_benchmark.cpp", workspace / "validation/benchmarks/web.cpp")
        shutil.copyfile(repository / "validation/integration/sdk.c", workspace / "consumer.c")
        shutil.copyfile(sources / "dependency.c", workspace / "dependency.c")
        shutil.copyfile(sources / "consumer.c", workspace / "library.c")
        for linkage in ["static", "shared"]:
            dependency_linkage = ("shared" if linkage == "static" else "static") if mixed else linkage
            values = {
                "version": version,
                "toolchain_sha256": checksum(toolchain),
                "linkage": linkage,
                "dependency_linkage": dependency_linkage,
                "alternate_linkage": "shared" if dependency_linkage == "static" else "static",
                "alternate_static": "0" if dependency_linkage == "static" else "1",
                "static": "1" if linkage == "static" else "0",
                "dependency_archives": repr(pins["tetro_toolchain"]),
                "library_archives": repr(pins["toolchain_test"]),
                "dependency_pin": (sources / "dependency.tpl").read_text(),
                "dependencies": repr([] if linkage == "shared" and dependency_linkage == "static" else ["@dependency//:tetro_toolchain"]),
            }
            values["dependency_pin"] = substitute(values["dependency_pin"], values)
            for output, template in [("MODULE.bazel", "MODULE.tpl"), ("BUILD", "BUILD.tpl")]:
                (workspace / output).write_text(substitute((sources / template).read_text(), values))
            if linkage == "static" and not mixed:
                selected = subprocess.check_output([
                    "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                    "query", "labels(actual, //multiple:_validation_static)",
                    "--distdir=" + str(toolchain.parent),
                    "--distdir=" + str(directory),
                ], cwd=workspace, text=True).strip()
                assert selected == "//source:toolchain_test", selected
                print("Multiple SDK packages preserve the primary validation runtime.", flush=True)
                for action in ["--all", "--check"]:
                    subprocess.run([
                        "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                        "run", "//:format", "--distdir=" + str(toolchain.parent),
                        "--", action,
                    ], cwd=workspace, check=True)
                assert not (workspace / ".clang-format").exists()
                print("Candidate formatter passed in the external consumer.", flush=True)
                verify_vscode(root, workspace, toolchain, directory)
                subprocess.run([
                    "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                    "run", "//:tests", "--config=web",
                    "--distdir=" + str(toolchain.parent),
                    "--distdir=" + str(directory),
                ], cwd=workspace, check=True)
                print("Candidate Web validation runner passed.", flush=True)
            subprocess.run([
                "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                "test", "//:consumer", "//:component", "//:alternate/consumer", "//:consumer_library_shared", "//:repack", "--nocache_test_results",
                "--distdir=" + str(toolchain.parent), "--distdir=" + str(directory),
            ], cwd=workspace, check=True)
            print(linkage + " SDK consumer passed", flush=True)
            output_directory = workspace / ".bin/bin"
            if not output_directory.exists():
                output_directory = workspace / "bazel-bin"
            subprocess.run([sys.executable, str(Path(__file__).resolve()), "--load-consumer",
                            str(output_directory / "libconsumer_library.so"), str(host)], check=True)
            if linkage == "static":
                dynamic = subprocess.run(["readelf", "-d", str(output_directory / "consumer")], capture_output=True, text=True, check=True).stdout
                assert ("libdependency_shared.so" in dynamic) == (dependency_linkage == "shared"), dynamic
                if dependency_linkage == "static":
                    assert "libruntime.so" not in dynamic, dynamic
            assert not list(output_directory.glob("*-source.zip"))
            original = directory / ("toolchain_test-" + version + "-linux-x86_64-v3-" + linkage + ".zip")
            repacked = output_directory / original.name
            with zipfile.ZipFile(original) as before, zipfile.ZipFile(repacked) as after:
                before_components = json.loads(before.read("sdk.json"))["components"]
                after_components = json.loads(after.read("sdk.json"))["components"]
                assert before_components == after_components, (before_components, after_components)
                before_runtime = json.loads(before.read("sdk.json"))["runtime"]
                after_runtime = json.loads(after.read("sdk.json"))["runtime"]
                assert before_runtime == after_runtime
                before_system = json.loads(before.read("sdk.json"))["system"]
                after_system = json.loads(after.read("sdk.json"))["system"]
                assert [item["interface"] for item in before_system] == [item["interface"] for item in after_system]
                for original_interface, repacked_interface in zip(before_system, after_system):
                    # Explicit SDK dependencies can contribute further options.
                    # The original option sequence must survive repackaging.
                    remaining = iter(repacked_interface["linkopts"])
                    assert all(flag in remaining for flag in original_interface["linkopts"])
                assert len(after.namelist()) == len(set(after.namelist()))
                for library in after_runtime:
                    assert before.read(library["library"]) == after.read(library["library"])
                # Declared SDKs may give an identical archive its public name.
                # Compare contents rather than relying on the producer's target
                # basename surviving the independent import and repackage.
                before_archives = json.loads(before.read("sdk.json"))["archives"]
                after_archives = json.loads(after.read("sdk.json"))["archives"]
                assert sorted(checksum_bytes(before.read(item["library"])) for item in before_archives) == sorted(checksum_bytes(after.read(item["library"])) for item in after_archives)
            if linkage == "shared":
                verify_runtime(root / "repacked", repacked, host)
            for platform in ["windows_x64", "wasm32"]:
                subprocess.run([
                    "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                    "build", "//:consumer", "//:component", "//:alternate/consumer", "//:consumer_library_shared", "--platforms=@tetro_toolchain//:" + platform,
                    "--distdir=" + str(toolchain.parent), "--distdir=" + str(directory),
                ], cwd=workspace, check=True)
                print(linkage + " SDK consumer built for " + platform, flush=True)
                if platform == "windows_x64":
                    for directory_name in ["", "alternate"]:
                        assert (output_directory / directory_name / "plugin.dll").is_file()
            if linkage == "static":
                # The complete SDK can link using only its bundled dependencies.
                # Component header imports remain separately declared.
                standalone = dict(values, dependencies="[]")
                (workspace / "MODULE.bazel").write_text(substitute((sources / "MODULE.tpl").read_text(), standalone))
                subprocess.run([
                    "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                    "test", "//:consumer", "--nocache_test_results",
                    "--distdir=" + str(toolchain.parent), "--distdir=" + str(directory),
                ], cwd=workspace, check=True)
                print("Static SDK linked using bundled dependencies.", flush=True)
                verify_dependency_conflict(root, workspace, toolchain, directory, dependency_directory,
                                           sources, values, pins["tetro_toolchain"])
        if mixed:
            # The shared SDK embeds static code, while its public component
            # introduces the dependency SDK separately. Conflicting runtimes
            # must fail even though the aggregate declares no link dependency.
            verify_dependency_conflict(root, workspace, toolchain, directory, dependency_directory,
                                       sources, values, pins["tetro_toolchain"], component=True)
        else:
            verify_missing_variant(root, workspace, toolchain, directory, sources, values, pins["toolchain_test"])
        metadata = verify_runtime(root / "relocated", directory / ("toolchain_test-" + version + "-linux-x86_64-v3-shared.zip"), host)
        # The release manifest owns every relocated path, so fixture target
        # names can evolve independently from this collision check.
        if metadata["runtime"]:
            verify_conflict(root, repository / "source/bazel/release/package.py",
                            root / "relocated" / metadata["library"],
                            root / "relocated" / metadata["runtime"][0]["library"])


if __name__ == "__main__":
    if sys.argv[1] in ["--load", "--load-consumer"]:
        import ctypes
        if len(sys.argv) > 3:
            ctypes.CDLL(sys.argv[3], mode=ctypes.RTLD_GLOBAL)
        library = ctypes.CDLL(sys.argv[2])
        if sys.argv[1] == "--load-consumer":
            assert library.toolchain_consumer_entry(21) == 42
        else:
            assert library.toolchain_c_entry(20) == 21
            assert library.toolchain_cpp_entry(21) == 42
    else:
        from python.runfiles import runfiles
        resolver = runfiles.Create()
        toolchain, matching, mixed, host = [Path(resolver.Rlocation(argument)).resolve() for argument in sys.argv[1:]]
        repository = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix="toolchain-private-header-") as temporary:
            verify_private_header_boundary(
                Path(temporary),
                repository / "source/bazel/release/package.py",
            )
        # Nested Bazel commands establish their own workspace for formatter
        # and editor installation, including when this test uses `bazel run`.
        os.environ.pop("BUILD_WORKSPACE_DIRECTORY", None)
        os.environ.pop("BUILD_WORKING_DIRECTORY", None)
        verify(toolchain, matching, matching, host)
        verify(toolchain, mixed, matching, host, mixed=True)
