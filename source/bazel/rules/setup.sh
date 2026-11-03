#!/bin/sh
set -eu
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  cd "$BUILD_WORKSPACE_DIRECTORY"
fi
destination=".vscode"
mkdir -p "$destination"
source_directory="${0%.*}.files"

for configuration in "$source_directory/"*.json; do
  output="$destination/${configuration##*/}"
  if ! cmp -s "$configuration" "$output"; then
    cp -f "$configuration" "$output"
  fi
done
if ! cmp -s "$source_directory/.bazelrc" .bazelrc; then
  cp -f "$source_directory/.bazelrc" .bazelrc
fi
echo "Installed Bazel and VS Code configuration."
