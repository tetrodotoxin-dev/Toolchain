// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include <stdio.h>

namespace Toolchain::Validation {

// Test streams use writable temporary storage and binary mode on either host.
// The caller closes the returned FILE. No filename survives its final close.
auto temporary_stream() -> FILE*;

// Supplies a writable stream whose backing resource rejects writes. Buffering
// remains under the test's control so content and flush failures stay distinct.
auto failing_stream() -> FILE*;

}  // namespace Toolchain::Validation
