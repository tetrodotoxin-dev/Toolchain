// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "tests/library.h"

int main(void) {
  return toolchain_c_entry(20) == 21 && toolchain_cpp_entry(21) == 42 ? 0 : 1;
}
