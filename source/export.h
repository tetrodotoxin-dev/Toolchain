// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#ifndef TOOLCHAIN_EXPORT_H
#define TOOLCHAIN_EXPORT_H

// Mark a function definition that a host looks up in a shared library.
// Other definitions keep the toolchain's hidden visibility. The annotation
// controls symbol publication, while the declaration retains its own language
// linkage. C++ providers use C linkage for entrypoints shared with other hosts.
#if defined(_WIN32)
#define TOOLCHAIN_EXPORT __declspec(dllexport)
#else
#define TOOLCHAIN_EXPORT __attribute__((visibility("default")))
#endif

#endif
