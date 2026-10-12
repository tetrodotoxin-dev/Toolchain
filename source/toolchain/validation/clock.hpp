// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

namespace Toolchain::Validation {

// Clock reads the host monotonic counter in nanoseconds. Values share an
// unspecified epoch and support elapsed time subtraction within one process.
// Wall clock adjustments therefore cannot move validation deadlines or
// benchmark samples.
class Clock {
 public:
  auto time_ns() const -> U64;
};

}  // namespace Toolchain::Validation
