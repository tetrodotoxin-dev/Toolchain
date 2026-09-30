// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#ifndef TOOLCHAIN_TEST_LIBRARY_H
#define TOOLCHAIN_TEST_LIBRARY_H

// Both implementation languages publish ordinary C entrypoints. A consumer
// uses the same declarations when linking the archive or loading the library.
#ifdef __cplusplus
extern "C" {
#endif

int toolchain_c_entry(int value);
int toolchain_cpp_entry(int value);

#ifdef __cplusplus
}
#endif

#endif
