// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/toolchain.h"

C_LINKAGE EXPORTED(TOOLCHAIN_PLUGIN)
S32 toolchain_plugin_entry(S32 value) {
  return value;
}
