// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/library.h"

#if EXPECT_COMPONENT && __has_include("validation/optional.h")
#error The selected SDK component exposes an unrelated header.
#endif

#if EXPECT_STATIC
#if !TOOLCHAIN_TEST_STATIC
#error Static SDK consumers need the public library's static definition.
#endif

#else
#if defined(TOOLCHAIN_TEST_STATIC) || defined(TETRO_TOOLCHAIN_STATIC)
#error Shared SDK consumers must preserve import declarations.
#endif
#endif

#if defined(TOOLCHAIN_PROJECT_VALUE) || defined(TETRO_TOOLCHAIN_STATIC) || \
    defined(TOOLCHAIN_PRIVATE_STATIC)
#error SDK consumers must not receive implementation dependency definitions.
#endif

#if __has_include(         \
    "project_detail.h") || \
    __has_include("validation/project.h") || __has_include("validation/runtime.h")
#error SDK consumers must not receive implementation dependency headers.
#endif

#if defined(TOOLCHAIN_TEST_EXPORT) || defined(TETRO_TOOLCHAIN_EXPORT)
#error SDK consumers must not receive export definitions.
#endif

#ifdef TOOLCHAIN_TEST_PRIVATE
#error SDK consumers must not receive private definitions.
#endif

#if defined(__linux__)
// The public linker option redirects this declaration to its implementation.
// Without that option the consumer has an unresolved call to the probe.
int toolchain_link_probe(void);
int __wrap_toolchain_link_probe(void) {
  return TOOLCHAIN_TEST_VALUE;
}
#endif

int main(void) {
  const int valid = toolchain_c_entry(20) == TOOLCHAIN_TEST_VALUE &&
                    toolchain_cpp_entry(21) == 42;
#if defined(__linux__)
  return valid && toolchain_link_probe() == TOOLCHAIN_TEST_VALUE ? 0 : 1;
#else
  return valid ? 0 : 1;
#endif
}
