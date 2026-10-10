// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#ifndef TOOLCHAIN_TOOLCHAIN_H
#define TOOLCHAIN_TOOLCHAIN_H

#include "toolchain/export.h"

// Target macros follow the selected compiler target during native and cross
// compilation. Source implementations use them to select their system edge.
#ifdef __wasm__
#define TOOLCHAIN_WASM
#elif defined(_WIN32)
#define TOOLCHAIN_WINDOWS
#elif defined(__linux__)
#define TOOLCHAIN_LINUX
#endif

// The shared scalar vocabulary gives C and C++ interfaces one fixed data
// layout. CppSize names the compiler address width for native system calls.
typedef unsigned char U8;
typedef unsigned short int U16;
typedef unsigned long long U64;

typedef signed char S8;
typedef signed short int S16;
typedef signed long long S64;

// Handle the LP32 edge case between int and long.
#ifdef __LP32__

typedef unsigned long U32;
typedef signed long S32;

#else

typedef unsigned int U32;
typedef signed int S32;

#endif

typedef float R32;
typedef double R64;
typedef U64 Count;
typedef __SIZE_TYPE__ CppSize;

#ifdef __cplusplus
#define TOOLCHAIN_ASSERT static_assert
#else
#define TOOLCHAIN_ASSERT _Static_assert
#endif

TOOLCHAIN_ASSERT(sizeof(U8) == 1, "U8 requires one byte");
TOOLCHAIN_ASSERT(sizeof(U16) == 2, "U16 requires two bytes");
TOOLCHAIN_ASSERT(sizeof(U32) == 4, "U32 requires four bytes");
TOOLCHAIN_ASSERT(sizeof(U64) == 8, "U64 requires eight bytes");
TOOLCHAIN_ASSERT(sizeof(S8) == 1, "S8 requires one byte");
TOOLCHAIN_ASSERT(sizeof(S16) == 2, "S16 requires two bytes");
TOOLCHAIN_ASSERT(sizeof(S32) == 4, "S32 requires four bytes");
TOOLCHAIN_ASSERT(sizeof(S64) == 8, "S64 requires eight bytes");
TOOLCHAIN_ASSERT(sizeof(R32) == 4, "R32 requires four bytes");
TOOLCHAIN_ASSERT(sizeof(R64) == 8, "R64 requires eight bytes");

#endif
