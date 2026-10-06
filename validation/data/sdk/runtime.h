// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#ifndef TOOLCHAIN_TEST_RUNTIME_H
#define TOOLCHAIN_TEST_RUNTIME_H

#include "toolchain/export.h"

C_LINKAGE EXPORTED(TOOLCHAIN_RUNTIME)
int toolchain_runtime_entry(int value);

#endif
