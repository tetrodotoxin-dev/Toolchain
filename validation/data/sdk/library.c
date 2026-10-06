// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/library.h"

#include "project_detail.h"
#include "validation/data/sdk/project.h"

#ifndef TOOLCHAIN_TEST_PRIVATE
#error The implementation requires its private definition.
#endif

#ifdef TETRO_TOOLCHAIN_EXPORT
#error A dependency's export flag reached this implementation.
#endif

C_LINKAGE HIDDEN int toolchain_private_entry(int value);

// External linkage makes this helper a useful check of the visibility default.
// It participates in the linked implementation with local symbol visibility.
int toolchain_c_helper(int value) {
  return toolchain_private_entry(toolchain_project_entry(value)) + 1;
}

C_LINKAGE int toolchain_c_entry(int value) {
  return toolchain_c_helper(value);
}
