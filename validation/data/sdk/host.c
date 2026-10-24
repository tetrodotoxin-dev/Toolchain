// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/host.h"

C_LINKAGE S32 toolchain_host_entry(S32 value) {
  return value;
}
