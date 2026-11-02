#!/bin/sh
set -eu
destination=".vscode"
mkdir -p "$destination"
source_directory="${0%.*}.files"

# Bazel outputs are read only, including copies from an earlier install.
cp -f "$source_directory/"*.json "$destination/"
"$(dirname "$0")/format.sh" --export-configuration "$destination/.clang-format"
