// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/export.h"

// External linkage makes this helper a useful check of the visibility default.
// It participates in the linked implementation but has no export annotation.
int toolchain_c_helper(int value) {
  return value + 1;
}

TOOLCHAIN_EXPORT int toolchain_c_entry(int value) {
  return toolchain_c_helper(value);
}
