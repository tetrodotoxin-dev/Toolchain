// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/project.h"

#include "validation/data/sdk/runtime.h"

#ifdef TOOLCHAIN_TEST_EXPORT
#error A dependent library's export flag reached this implementation.
#endif

C_LINKAGE S32 toolchain_project_entry(S32 value) {
  return toolchain_runtime_entry(value);
}
