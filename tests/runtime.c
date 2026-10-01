// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "tests/runtime.h"

C_LINKAGE int toolchain_runtime_entry(int value) {
  return value;
}
