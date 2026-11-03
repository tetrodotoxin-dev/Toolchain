#!/bin/sh

set -eu
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  cd "$BUILD_WORKSPACE_DIRECTORY"
fi

runfiles="$0.runfiles"
if [ ! -d "$runfiles" ]; then
  runfiles="${RUNFILES_DIR:?Web validation runfiles are unavailable}"
fi
exec "$runfiles/__NODE__" "$runfiles/__PROGRAM__" "$@"
