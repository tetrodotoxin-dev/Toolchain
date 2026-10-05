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
        seen = {}
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for source, name in sorted(files, key=lambda entry: entry[1]):
                if name.startswith("/") or ".." in Path(name).parts:
                    raise ValueError(f"Invalid archive entry: {name}")
                content = Path(source).read_bytes()
                if name == "sdk.json":
                    # lib/ sorts before sdk.json, so these digests describe the
                    # exact payloads already admitted to this archive.
                    metadata = json.loads(content)
                    metadata["sha256"] = {path: digest for path, digest in seen.items()
                                          if path.startswith("lib/")}
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
