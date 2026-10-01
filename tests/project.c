// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "tests/project.h"

#include "tests/runtime.h"

#ifdef TOOLCHAIN_TEST_EXPORT
#error A dependent library's export flag reached this implementation.
#endif

C_LINKAGE int toolchain_project_entry(int value) {
  return toolchain_runtime_entry(value);
}
