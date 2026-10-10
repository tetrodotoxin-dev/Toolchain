// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#ifndef TOOLCHAIN_TEST_RUNTIME_H
#define TOOLCHAIN_TEST_RUNTIME_H

#include "toolchain/toolchain.h"

C_LINKAGE EXPORTED(TOOLCHAIN_RUNTIME)
S32 toolchain_runtime_entry(S32 value);

#endif
