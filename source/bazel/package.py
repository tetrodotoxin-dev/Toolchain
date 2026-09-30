# Copyright (c) 2023-present Matt Kaes and contributors

"""Archive the exact files supplied by the release rule without running builds."""

import hashlib
import json
from pathlib import Path
import sys
import zipfile


def package(manifest, checksums):
    digests = []
    for destination, files in json.loads(Path(manifest).read_text()).items():
        seen = set()
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for source, name in sorted(files, key=lambda entry: entry[1]):
                if name in seen or name.startswith("/") or ".." in Path(name).parts:
                    raise ValueError(f"Invalid or duplicate archive entry: {name}")
                seen.add(name)
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (0o100755 if Path(source).stat().st_mode & 0o111 else 0o100644) << 16
                archive.writestr(info, Path(source).read_bytes(), compresslevel=9)
        digest = hashlib.sha256(Path(destination).read_bytes()).hexdigest()
        digests.append(f"{digest}  {Path(destination).name}\n")
    Path(checksums).write_text("".join(digests))


if __name__ == "__main__":
    package(*sys.argv[1:])
