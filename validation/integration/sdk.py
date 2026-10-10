# Copyright (c) 2023-present Matt Kaes and contributors

"""Consume Toolchain's built SDK fixtures through the real repository importer.

The //validation:sdk test supplies the candidate source and
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


def substitute(template, values):
    for key, value in values.items():
        template = template.replace("{" + key + "}", value)
    return template


def verify_runtime(directory, archive_path):
    with zipfile.ZipFile(archive_path) as archive:
        archive.extractall(directory)
    metadata = json.loads((directory / "sdk.json").read_text())
    # A new process observes the extracted libraries and host platform runtime,
    # giving relocation an independent loader state after the build checks.
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("LD_", "RUNFILES_"))}
    command = [sys.executable, str(Path(__file__).resolve()), "--load",
               str(directory / metadata["library"])]
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


def verify_dependency_conflict(root, workspace, toolchain, directory, sources, values, pins):
    altered = root / "conflicting"
    altered.mkdir()
    name = "tetro_toolchain-" + values["version"] + "-linux-x86_64-v3-static.zip"
    with zipfile.ZipFile(directory / name) as original:
        contents = {entry: original.read(entry) for entry in original.namelist()}
    metadata = json.loads(contents["sdk.json"])
    path = metadata["runtime"][0]["library"]
    contents[path] += b"different runtime fixture"
    metadata["sha256"][path] = hashlib.sha256(contents[path]).hexdigest()
    contents["sdk.json"] = json.dumps(metadata).encode()
    with zipfile.ZipFile(altered / name, "w") as archive:
        for path, content in contents.items():
            archive.writestr(path, content)
    conflict = dict(values)
    conflict["dependency_archives"] = repr(dict(pins, **{
        "linux-x86_64-v3-static": checksum(altered / name),
    }))
    conflict["dependency_pin"] = substitute((sources / "dependency.tpl").read_text(), conflict)
    (workspace / "MODULE.bazel").write_text(substitute((sources / "MODULE.tpl").read_text(), conflict))
    result = subprocess.run([
        "bazel", "--batch", "--output_base=" + str(root / "bazel"),
        "build", "//:consumer", "--distdir=" + str(altered),
        "--distdir=" + str(toolchain.parent), "--distdir=" + str(directory),
    ], cwd=workspace, capture_output=True, text=True)
    assert result.returncode != 0 and "Bundled runtime disagrees with a declared SDK dependency" in result.stderr, result.stderr
    print("Incompatible SDK dependency was rejected during import.", flush=True)


def verify(toolchain, checksum_manifest):
    toolchain = Path(toolchain).resolve()
    directory = Path(checksum_manifest).resolve().parent
    version = toolchain.name.removeprefix("tetro_toolchain-").removesuffix("-source.tar.gz")
    repository = Path(__file__).resolve().parents[2]
    sources = repository / "validation/data/sdk"
    with tarfile.open(toolchain, "r:gz") as archive:
        packaged_sources = set(archive.getnames())
    assert "source/bazel/rules/.clang-format.tpl" in packaged_sources
    assert ".clang-format" not in packaged_sources

    pins = {}
    for project in ["tetro_toolchain", "toolchain_test"]:
        prefix = project + "-" + version + "-"
        pins[project] = {}
        # The checksum manifest is the exact archive inventory for this release.
        # Selecting its entries isolates the candidate from other build outputs.
        manifest = directory / (prefix + "sha256.txt")
        for entry in manifest.read_text().splitlines():
            digest, name = entry.split(maxsplit=1)
            assert name.startswith(prefix) and name.endswith(".zip"), name
            path = directory / name
            assert checksum(path) == digest, path
            key = path.name.removeprefix(prefix).removesuffix(".zip")
            if key == "source":
                continue
            pins[project][key] = digest
            with zipfile.ZipFile(path) as archive:
                if key == "headers":
                    for name in [
                        "toolchain/export.h",
                        "toolchain/memory/lifetime.hpp",
                        "toolchain/toolchain.h",
                        "toolchain/toolchain.hpp",
                    ]:
                        assert "include/" + name in archive.namelist()
                    if project == "toolchain_test":
                        assert "include/validation/data/sdk/public.h" in archive.namelist()
                        for name in ["project.h", "runtime.h", "project_detail.h"]:
                            assert not any(path.endswith("/" + name) for path in archive.namelist()), archive.namelist()
                    continue
                metadata = json.loads(archive.read("sdk.json"))
                assert metadata["linkage"] == key.rsplit("-", 1)[1]
                assert metadata["project"] == project.upper()
                assert metadata["library"] in archive.namelist()
                runtime = metadata["runtime"]
                assert len(runtime) == (2 if project == "toolchain_test" and key.endswith("-shared") else 1)
                assert len(archive.namelist()) == len(set(archive.namelist()))
                for library in runtime:
                    assert library["library"] in archive.namelist()
                    if key.startswith("windows-"):
                        assert library["interface"] in archive.namelist()
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
        (workspace / "source").mkdir()
        shutil.copyfile(sources / "source.tpl", workspace / "source/BUILD.bazel")
        shutil.copyfile(sources / "style.cpp", workspace / "source/style.cpp")
        shutil.copyfile(repository / "validation/integration/sdk.c", workspace / "consumer.c")
        for linkage in ["static", "shared"]:
            values = {
                "version": version,
                "toolchain_sha256": checksum(toolchain),
                "linkage": linkage,
                "static": "1" if linkage == "static" else "0",
                "dependency_archives": repr(pins["tetro_toolchain"]),
                "library_archives": repr(pins["toolchain_test"]),
                "dependency_pin": (sources / "dependency.tpl").read_text(),
                "dependencies": repr(["@dependency//:tetro_toolchain"]),
            }
            values["dependency_pin"] = substitute(values["dependency_pin"], values)
            for output, template in [("MODULE.bazel", "MODULE.tpl"), ("BUILD.bazel", "BUILD.tpl")]:
                (workspace / output).write_text(substitute((sources / template).read_text(), values))
            if linkage == "static":
                for action in ["--all", "--check"]:
                    subprocess.run([
                        "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                        "run", "//:format", "--distdir=" + str(toolchain.parent),
                        "--", action,
                    ], cwd=workspace, check=True)
                assert not (workspace / ".clang-format").exists()
                print("Candidate formatter passed in the external consumer.", flush=True)
            subprocess.run([
                "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                "test", "//:consumer", "//:component", "//:repack", "--nocache_test_results",
                "--distdir=" + str(toolchain.parent), "--distdir=" + str(directory),
            ], cwd=workspace, check=True)
            print(linkage + " SDK consumer passed", flush=True)
            original = directory / ("toolchain_test-" + version + "-linux-x86_64-v3-" + linkage + ".zip")
            repacked = workspace / "bazel-bin" / original.name
            with zipfile.ZipFile(original) as before, zipfile.ZipFile(repacked) as after:
                before_components = json.loads(before.read("sdk.json"))["components"]
                after_components = json.loads(after.read("sdk.json"))["components"]
                assert before_components == after_components, (before_components, after_components)
                before_runtime = json.loads(before.read("sdk.json"))["runtime"]
                after_runtime = json.loads(after.read("sdk.json"))["runtime"]
                assert before_runtime == after_runtime
                assert len(after.namelist()) == len(set(after.namelist()))
                for library in after_runtime:
                    assert before.read(library["library"]) == after.read(library["library"])
            if linkage == "shared":
                verify_runtime(root / "repacked", repacked)
            for platform in ["windows_x64", "wasm32"]:
                subprocess.run([
                    "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                    "build", "//:consumer", "//:component", "--platforms=@tetro_toolchain//:" + platform,
                    "--distdir=" + str(toolchain.parent), "--distdir=" + str(directory),
                ], cwd=workspace, check=True)
                print(linkage + " SDK consumer built for " + platform, flush=True)
            if linkage == "static":
                verify_dependency_conflict(root, workspace, toolchain, directory,
                                           sources, values, pins["tetro_toolchain"])
        metadata = verify_runtime(root / "relocated", directory / ("toolchain_test-" + version + "-linux-x86_64-v3-shared.zip"))
        # The release manifest owns every relocated path, so fixture target
        # names can evolve independently from this collision check.
        verify_conflict(root, repository / "source/bazel/release/package.py",
                        root / "relocated" / metadata["library"],
                        root / "relocated" / metadata["runtime"][0]["library"])


if __name__ == "__main__":
    if sys.argv[1] == "--load":
        import ctypes
        library = ctypes.CDLL(sys.argv[2])
        assert library.toolchain_c_entry(20) == 21
        assert library.toolchain_cpp_entry(21) == 42
    else:
        from python.runfiles import runfiles
        resolver = runfiles.Create()
        verify(*[Path(resolver.Rlocation(argument)) for argument in sys.argv[1:]])
