// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

// The base component preserves its scalar input across the fixture's public
// C boundary. Application depends on this declaration and its implementation.
C_LINKAGE EXPORTED(CONSUMER)
S32 consumer_base(S32 value);
