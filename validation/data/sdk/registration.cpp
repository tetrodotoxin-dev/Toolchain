// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/toolchain.h"

C_LINKAGE HIDDEN auto toolchain_runtime_initialize() -> void;

// This translation unit supplies initialization without a referenced symbol.
// Static SDK consumers need the archive's alwayslink requirement to retain it.
struct Registration {
  Registration() { toolchain_runtime_initialize(); }
};

static Registration registration;
