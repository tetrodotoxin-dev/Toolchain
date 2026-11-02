#!/bin/sh
set -eu
directory=${0%/*}
exec '__PYTHON__' "$directory/__DRIVER__" "$@"
