// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#ifndef TOOLCHAIN_EXPORT_H
#define TOOLCHAIN_EXPORT_H

// C linkage gives function declarations the same symbol name in C and C++.
// Export and hidden annotations select symbol visibility independently.
#ifdef __cplusplus
#define C_LINKAGE extern "C"
#else
#define C_LINKAGE
#endif

// A shared library exports its public declarations, and consumers import
// those declarations. Static consumers use ordinary declarations.
#if defined(_WIN32)
#define TOOLCHAIN_EXPORT __declspec(dllexport)
#define TOOLCHAIN_IMPORT __declspec(dllimport)
#else
#define TOOLCHAIN_EXPORT __attribute__((visibility("default")))
#define TOOLCHAIN_IMPORT __attribute__((visibility("default")))
#endif

// Hidden symbols remain available throughout their own executable or shared
// library. ELF binds those references locally. Windows keeps declarations
// private by omitting export annotations and using explicit export tables.
#if defined(_WIN32)
#define HIDDEN
#else
#define HIDDEN __attribute__((visibility("hidden")))
#endif

// A recognized flag expands to a pair whose second argument is the annotation.
// Other flags leave one argument, so selection uses the supplied fallback.
// Expand flag values before concatenating them with the lookup prefix.
#define TOOLCHAIN_DETAIL_SECOND(first, second, ...) second
#define TOOLCHAIN_DETAIL_SELECT(...) TOOLCHAIN_DETAIL_SECOND(__VA_ARGS__, 0)
#define TOOLCHAIN_DETAIL_LOOKUP_RAW(prefix, flag, fallback) \
  TOOLCHAIN_DETAIL_SELECT(prefix##flag, fallback)
#define TOOLCHAIN_DETAIL_LOOKUP(prefix, flag, fallback) \
  TOOLCHAIN_DETAIL_LOOKUP_RAW(prefix, flag, fallback)
#define TOOLCHAIN_DETAIL_EXPORT_1 0, TOOLCHAIN_EXPORT
#define TOOLCHAIN_DETAIL_STATIC_1 0,

// EXPORTED(TTX) imports by default. Compile the shared implementation with
// TTX_EXPORT=1 to export its declarations. TTX_STATIC=1 selects ordinary
// declarations for both a static implementation and its consumers, taking
// precedence over TTX_EXPORT. Each flag governs only its named library.
#define EXPORTED(project)                         \
  TOOLCHAIN_DETAIL_LOOKUP(                        \
      TOOLCHAIN_DETAIL_STATIC_, project##_STATIC, \
      TOOLCHAIN_DETAIL_LOOKUP(                    \
          TOOLCHAIN_DETAIL_EXPORT_, project##_EXPORT, TOOLCHAIN_IMPORT))

#endif
