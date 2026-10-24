// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/library.h"

C_LINKAGE EXPORTED(TOOLCHAIN_CONSUMER)
S32 toolchain_consumer_entry(S32 value) {
  return toolchain_cpp_entry(value);
}
