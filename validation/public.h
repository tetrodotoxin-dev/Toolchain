// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#ifndef TOOLCHAIN_TEST_PUBLIC_H
#define TOOLCHAIN_TEST_PUBLIC_H

#if TOOLCHAIN_TEST_PUBLIC != 1
#error A public dependency's definition must reach consumers.
#endif

#endif
