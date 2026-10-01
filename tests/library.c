// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "tests/library.h"

#include "tests/project.h"

#ifndef TOOLCHAIN_TEST_PRIVATE
#error The implementation requires its private definition.
#endif

#ifdef TETRO_TOOLCHAIN_EXPORT
#error A dependency's export flag reached this implementation.
#endif

// External linkage makes this helper a useful check of the visibility default.
// It participates in the linked implementation but has no export annotation.
int toolchain_c_helper(int value) {
  return toolchain_project_entry(value) + 1;
}

C_LINKAGE int toolchain_c_entry(int value) {
  return toolchain_c_helper(value);
}
