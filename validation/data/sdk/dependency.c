// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/project.h"

#if EXPECT_STATIC != defined(TETRO_TOOLCHAIN_STATIC)
#error The independent dependency variant must supply matching declarations.
#endif

S32 main(void) {
  return toolchain_project_entry(7) == 7 ? 0 : 1;
}
