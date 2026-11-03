# Copyright (c) 2023-present Matt Kaes and contributors

"""Compare four source fixtures with their formatted bytes and diagnostics."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

def run(formatter, root, *arguments, status=0):
    result = subprocess.run(
        [str(formatter), *arguments], cwd=root,
        capture_output=True, text=True,
        env=dict(os.environ, BUILD_WORKSPACE_DIRECTORY=str(root)),
    )
    assert result.returncode == status, result.stdout + result.stderr
    return result


if __name__ == "__main__":
    formatter = Path(".bin/bin/format.cmd" if os.name == "nt" else ".bin/bin/format.sh").resolve()
    fixtures = Path("validation/data/format")
    with tempfile.TemporaryDirectory(prefix="toolchain-format-") as temporary:
        root = Path(temporary)
        source = root / "source/example/module"
        source.mkdir(parents=True)
        shutil.copyfile(fixtures / "module.tpl", root / "MODULE.bazel")
        for extension in ["cpp", "hpp"]:
            shutil.copyfile(fixtures / ("before." + extension + ".tpl"), source / ("value." + extension))
        for arguments in [[], ["--all"]]:
            run(formatter, root, *arguments)
            for extension in ["cpp", "hpp"]:
                assert (source / ("value." + extension)).read_bytes() == (fixtures / ("after." + extension + ".tpl")).read_bytes()
        header = source / "value.hpp"
        canonical = header.read_text(encoding="utf-8")
        header.write_text(canonical.replace("// Value retains", "// This helper simply provides a robust solution.\n// Value retains"), encoding="utf-8", newline="\n")
        run(formatter, root, str(header), status=1)
        result = run(formatter, root, "--no_comment_checks", str(header))
        assert "Comment quality:" not in result.stdout and not result.stderr, result.stdout + result.stderr
        header.write_text(canonical, encoding="utf-8", newline="\n")
        for extension in ["cpp", "hpp"]:
            shutil.copyfile(fixtures / ("invalid.before." + extension + ".tpl"), source / ("broken." + extension))
        result = run(formatter, root, "source/example/module/broken.cpp", "source/example/module/broken.hpp", status=1)
        assert result.stderr.replace(str(root), "<workspace>").replace("\\", "/") == (fixtures / "errors.txt").read_text(encoding="utf-8"), result.stderr
        result = run(formatter, root, "--no_comment_checks", "source/example/module/broken.cpp", "source/example/module/broken.hpp", status=1)
        assert "comment quality" not in result.stderr.lower(), result.stderr
        assert "raw allocation is restricted" in result.stderr, result.stderr
        for extension in ["cpp", "hpp"]:
            assert (source / ("broken." + extension)).read_bytes() == (fixtures / ("invalid.after." + extension + ".tpl")).read_bytes()
        run(formatter, root, "--export-configuration", ".vscode/.clang-format")
        configuration = (root / ".vscode/.clang-format").read_bytes()
        assert configuration.index(b"toolchain/") < configuration.index(b"runtime/") < configuration.index(b"foundation/")
        assert not (root / ".clang-format").exists()
    print("Four formatter fixtures matched expected bytes and diagnostics; repeat formatting preserved the output.")
