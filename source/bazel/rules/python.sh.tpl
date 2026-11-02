#!/bin/sh
set -eu
directory=${0%/*}
exec '__PYTHON__' -I -B "$directory/__DRIVER__" __ARGUMENTS__ "$@"
