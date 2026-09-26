#!/bin/sh
# LLD selects library mode before expanding Bazel response files.
exec /usr/bin/lld-link /lib "$@"
