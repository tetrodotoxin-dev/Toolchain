// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/validation/bytes.hpp"

namespace Toolchain::Validation {

// Registration borrows static names and callbacks. Keeping this record free of
// project types lets the runner test a library whose allocator or logging is
// itself under investigation.
struct Harness {
  Bytes<> name;
  void (*init)() = nullptr;
  void (*setup)() = nullptr;
  void (*teardown)() = nullptr;
};

}  // namespace Toolchain::Validation
