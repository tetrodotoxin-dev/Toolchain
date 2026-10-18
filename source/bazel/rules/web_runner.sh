#!/usr/bin/env bash

set -euo pipefail

runfiles="$0.runfiles"
if [[ ! -d "$runfiles" ]]; then
  runfiles="${RUNFILES_DIR:?Web validation runfiles are unavailable}"
fi
exec "$runfiles/_main/__NODE__" "$runfiles/_main/__PROGRAM__"
