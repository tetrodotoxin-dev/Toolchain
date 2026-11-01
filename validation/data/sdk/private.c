// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/toolchain.h"

// The alwayslink archive contributes this helper to the shared library.
// The consumer defines its own helper with this name, so leaking the archive
// into that executable produces a duplicate definition.
C_LINKAGE HIDDEN S32 toolchain_private_entry(S32 value) {
  return value;
}
