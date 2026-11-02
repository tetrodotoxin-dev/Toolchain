// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

// `consumer_value` increments a scalar through the public C interface. The
// release fixture links this declaration into its test program before it
// archives the same implementation.
C_LINKAGE EXPORTED(CONSUMER)
S32 consumer_value(S32 value);
