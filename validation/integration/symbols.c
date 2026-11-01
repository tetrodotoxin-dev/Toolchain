// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/toolchain.h"

// This consumer's helper has the same name as the shared library's hidden
// helper and a different result. A leaked alwayslink archive produces a
// duplicate definition. Accidental interposition fails the runtime check.
C_LINKAGE HIDDEN S32 toolchain_private_entry(S32 value) {
  return value == 0;
}
