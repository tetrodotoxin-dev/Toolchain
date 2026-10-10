// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/toolchain.h"
#include "validation/data/sdk/library.h"

_Static_assert(sizeof(U8) == 1, "U8 requires one byte");
_Static_assert(sizeof(U16) == 2, "U16 requires two bytes");
_Static_assert(sizeof(U32) == 4, "U32 requires four bytes");
_Static_assert(sizeof(U64) == 8, "U64 requires eight bytes");
_Static_assert(sizeof(S8) == 1, "S8 requires one byte");
_Static_assert(sizeof(S16) == 2, "S16 requires two bytes");
_Static_assert(sizeof(S32) == 4, "S32 requires four bytes");
_Static_assert(sizeof(S64) == 8, "S64 requires eight bytes");
_Static_assert(sizeof(R32) == 4, "R32 requires four bytes");
_Static_assert(sizeof(R64) == 8, "R64 requires eight bytes");
_Static_assert(sizeof(Count) == sizeof(U64), "Count uses the SDK width");

#if EXPECT_COMPONENT
#include "validation/data/sdk/project.h"

#if TOOLCHAIN_PROJECT_VALUE != 1
#error A component must receive its declared external dependency.
#endif

#if __has_include("validation/data/sdk/optional.h")
#error The selected SDK component exposes an unrelated header.
#endif

#else

#if __has_include("validation/data/sdk/project.h")
#error The complete SDK must keep implementation dependencies private.
#endif

#endif

#if EXPECT_STATIC
#if !TOOLCHAIN_TEST_STATIC
#error Static SDK consumers need the public library's static definition.
#endif

#else
#if defined(TOOLCHAIN_TEST_STATIC) || \
    (!EXPECT_COMPONENT && defined(TETRO_TOOLCHAIN_STATIC))
#error Shared SDK consumers must preserve import declarations.
#endif
#endif

#if (                                                                         \
    !EXPECT_COMPONENT &&                                                      \
    (defined(TOOLCHAIN_PROJECT_VALUE) || defined(TETRO_TOOLCHAIN_STATIC))) || \
    defined(TOOLCHAIN_PRIVATE_STATIC)
#error SDK implementation dependency definitions crossed the public boundary.
#endif

#if __has_include( \
    "project_detail.h") || __has_include("validation/data/sdk/runtime.h")
#error SDK implementation dependency headers crossed the public boundary.
#endif

#if defined(TOOLCHAIN_TEST_EXPORT) || defined(TETRO_TOOLCHAIN_EXPORT)
#error SDK export definitions crossed into consumer compilation.
#endif

#ifdef TOOLCHAIN_TEST_PRIVATE
#error SDK private definitions crossed into consumer compilation.
#endif

#if defined(__linux__)

// The public linker option redirects this declaration to the wrapper, proving
// that release metadata carries the consumer's required link behavior.
S32 toolchain_link_probe(void);
S32 __wrap_toolchain_link_probe(void) {
  return TOOLCHAIN_TEST_VALUE;
}

#endif

S32 main(void) {
  const S32 valid = toolchain_c_entry(20) == TOOLCHAIN_TEST_VALUE &&
                    toolchain_cpp_entry(21) == 42;

#if defined(__linux__)

  return valid && toolchain_link_probe() == TOOLCHAIN_TEST_VALUE ? 0 : 1;

#else

  return valid ? 0 : 1;

#endif
}
