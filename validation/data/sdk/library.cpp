// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/library.h"

// The C++ helper keeps native linkage. The entrypoint has C linkage and an
// independent export annotation for hosts that discover it by name.
HIDDEN auto toolchain_cpp_helper(int value) -> int {
  return value * 2;
}

C_LINKAGE auto toolchain_cpp_entry(int value) -> int {
  return toolchain_cpp_helper(value);
}
