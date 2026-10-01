# Copyright (c) 2023-present Matt Kaes and contributors

"""Consume Toolchain's built SDK fixtures through the real repository importer.

Build //:sdk, //tests:sdk and //tests:project_sdk first, then pass the source
tarball and fixture archive directory. Bazel's distdir supplies the exact
archives under their release URLs. This tests packaging before publication,
without editing a consuming project's dependency pins.
"""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def substitute(template, values):
    for key, value in values.items():
        template = template.replace("{" + key + "}", value)
    return template


def verify(toolchain, directory):
    toolchain = Path(toolchain).resolve()
    directory = Path(directory).resolve()
    version = toolchain.name.removeprefix("tetro_toolchain-").removesuffix("-source.tar.gz")
    sources = Path(__file__).resolve().parent
    pins = {}
    for project in ["tetro_toolchain", "toolchain_test"]:
        prefix = project + "-" + version + "-"
        pins[project] = {}
        for path in directory.glob(prefix + "*.zip"):
            key = path.name.removeprefix(prefix).removesuffix(".zip")
            if key == "source":
                continue
            pins[project][key] = checksum(path)
            with zipfile.ZipFile(path) as archive:
                if key == "headers":
                    assert "include/toolchain/export.h" in archive.namelist()
                    continue
                metadata = json.loads(archive.read("sdk.json"))
                assert metadata["linkage"] == key.rsplit("-", 1)[1]
                assert metadata["project"] == project.upper()
                assert metadata["library"] in archive.namelist()
                if project == "toolchain_test":
                    assert "TOOLCHAIN_TEST_VALUE=21" in metadata["defines"]
                    assert "TOOLCHAIN_TEST_PRIVATE=1" not in metadata["defines"]
                    assert "TOOLCHAIN_TEST_EXPORT=1" not in metadata["defines"]
                    expected_flags = ["-Wl,--wrap=toolchain_link_probe"] if key.startswith("linux-") else []
                    assert metadata["linkopts"] == expected_flags
                if metadata["interface"]:
                    assert metadata["interface"] in archive.namelist()
                if key == "windows-x86_64-msvc-static":
                    assert metadata["library"].endswith("_static.lib")

    # Only consumer configuration and a test source are created here. All SDK
    # headers, libraries and Bazel rules come from the archives being checked.
    with tempfile.TemporaryDirectory(prefix="toolchain-sdk-test-") as temporary:
        root = Path(temporary)
        workspace = root / "consumer"
        workspace.mkdir()
        shutil.copyfile(sources / "sdk_consumer.c", workspace / "consumer.c")
        for linkage in ["static", "shared"]:
            values = {
                "version": version,
                "toolchain_sha256": checksum(toolchain),
                "linkage": linkage,
                "static": "1" if linkage == "static" else "0",
                "dependency_archives": repr(pins["tetro_toolchain"]),
                "library_archives": repr(pins["toolchain_test"]),
            }
            for output, template in [("MODULE.bazel", "sdk.MODULE.tpl"), ("BUILD.bazel", "sdk.BUILD.tpl")]:
                (workspace / output).write_text(substitute((sources / template).read_text(), values))
            subprocess.run([
                "bazel", "--batch", "--output_base=" + str(root / "bazel"),
                "test", "//:consumer", "--nocache_test_results",
                "--distdir=" + str(toolchain.parent), "--distdir=" + str(directory),
            ], cwd=workspace, check=True)
            print(linkage + " SDK consumer passed", flush=True)


if __name__ == "__main__":
    verify(*sys.argv[1:])
