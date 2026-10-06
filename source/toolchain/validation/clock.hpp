// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include <stdint.h>

namespace Toolchain::Validation {

// Monotonic time keeps clock adjustments out of test deadlines and samples.
auto time_ns() -> uint64_t;

}  // namespace Toolchain::Validation
