// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

namespace Toolchain::Validation {

// Monotonic time keeps clock adjustments out of test deadlines and samples.
class Clock {
 public:
  auto time_ns() const -> U64;
};

}  // namespace Toolchain::Validation
