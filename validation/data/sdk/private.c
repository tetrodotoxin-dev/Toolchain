// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/toolchain.h"

// The linkage test looks for this hidden symbol in the shared library and its
// consumer to detect a private archive linked into both.
C_LINKAGE HIDDEN S32 toolchain_private_entry(S32 value) {
  return value;
}
