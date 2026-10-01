// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#ifndef TOOLCHAIN_TEST_LIBRARY_H
#define TOOLCHAIN_TEST_LIBRARY_H

#include "validation/public.h"
#include "toolchain/export.h"

#if TOOLCHAIN_TEST_VALUE != 21
#error The public definition must reach both the implementation and consumers.
#endif

// Both implementation languages publish ordinary C entrypoints. A consumer
// uses the same declarations when linking the archive or loading the library.
C_LINKAGE EXPORTED(TOOLCHAIN_TEST)
int toolchain_c_entry(int value);
C_LINKAGE EXPORTED(TOOLCHAIN_TEST)
int toolchain_cpp_entry(int value);

#endif
