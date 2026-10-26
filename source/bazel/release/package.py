# Copyright (c) 2023-present Matt Kaes and contributors

"""Archive the exact files already built and selected by the release rule."""

import hashlib
import json
from pathlib import Path
import posixpath
import re
import sys
import zipfile


PRIVATE_HEADER = re.compile(
    r"(?m)^[ \t]*#[ \t]*define[ \t]+TOOLCHAIN_PRIVATE_HEADER[ \t]+1[ \t]*$"
)
HEADER_INCLUDE = re.compile(
    r'(?m)^[ \t]*#[ \t]*include[ \t]*[<"]([^>"]+)[>"]'
)


def header_path(name):
    if not name.startswith("include/") or Path(name).suffix not in {".h", ".hpp"}:
        return None
    return name.removeprefix("include/")


def private_header_inventory(outputs):
    headers = {}
    for files in outputs.values():
        for source, name in files:
            path = header_path(name)
            if path is None:
                continue
            private = bool(PRIVATE_HEADER.search(Path(source).read_text()))
            if path in headers and headers[path][0][1] != private:
                raise ValueError(f"Conflicting private header classification: {path}")
            headers.setdefault(path, []).append((source, private))
    return headers


def validate_private_headers(headers):
    private = {path for path, entries in headers.items() if entries[0][1]}
    for path, entries in headers.items():
        if path in private:
            continue
        for source, _ in entries:
            for include in HEADER_INCLUDE.findall(Path(source).read_text()):
                relative = posixpath.normpath(
                    posixpath.join(posixpath.dirname(path), include)
                )
                dependency = include if include in private else relative
                if dependency in private:
                    raise ValueError(
                        f"Public header {path} includes private header {dependency}"
                    )
    return private


def package(manifest, checksums):
    outputs = json.loads(Path(manifest).read_text())
    private_headers = validate_private_headers(private_header_inventory(outputs))
    digests = []
    for destination, files in outputs.items():
        seen = {}
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for source, name in sorted(files, key=lambda entry: entry[1]):
                if name.startswith("/") or ".." in Path(name).parts:
                    raise ValueError(f"Invalid archive entry: {name}")
                packaged_header = header_path(name)
                if packaged_header in private_headers:
                    continue
                content = Path(source).read_bytes()
                if name == "sdk.json":
                    # Library and link interface paths sort before sdk.json,
                    # so these digests describe the payloads already archived.
                    metadata = json.loads(content)
                    for component in metadata.get("components", {}).values():
                        component["headers"] = [
                            header
                            for header in component["headers"]
                            if header not in private_headers
                        ]
                    metadata["sha256"] = {path: digest for path, digest in seen.items()
                                          if path.startswith(("lib/", "link/"))}
                    content = json.dumps(metadata, sort_keys=True).encode()
                digest = hashlib.sha256(content).hexdigest()
                # Different SDKs can carry the same dependency. Compare the
                # payloads before sharing its destination in the bundle.
                if name in seen:
                    if seen[name] != digest:
                        raise ValueError(f"Conflicting archive entry: {name}")
                    continue
                seen[name] = digest
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (0o100755 if Path(source).stat().st_mode & 0o111 else 0o100644) << 16
                archive.writestr(info, content, compresslevel=9)
        digest = hashlib.sha256(Path(destination).read_bytes()).hexdigest()
        digests.append(f"{digest}  {Path(destination).name}\n")
    Path(checksums).write_text("".join(digests))


if __name__ == "__main__":
    package(*sys.argv[1:])
