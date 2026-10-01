// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "tests/library.h"

// The C++ helper keeps native linkage. The entrypoint has C linkage and an
// independent export annotation for hosts that discover it by name.
HIDDEN int toolchain_cpp_helper(int value) {
  return value * 2;
}

C_LINKAGE int toolchain_cpp_entry(int value) {
  return toolchain_cpp_helper(value);
}
