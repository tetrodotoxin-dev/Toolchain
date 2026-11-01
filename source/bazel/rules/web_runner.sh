#!/bin/sh

set -eu

runfiles="$0.runfiles"
if [ ! -d "$runfiles" ]; then
  runfiles="${RUNFILES_DIR:?Web validation runfiles are unavailable}"
fi
exec "$runfiles/__NODE__" "$runfiles/__PROGRAM__" "$@"
