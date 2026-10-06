// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/library.h"

#if defined(TOOLCHAIN_TEST_EXPORT) || defined(TETRO_TOOLCHAIN_EXPORT)
#error An implementation's export flag reached its consumer.
#endif

#ifdef TOOLCHAIN_TEST_PRIVATE
#error An implementation's private definition reached its consumer.
#endif

#if defined(TOOLCHAIN_PROJECT_VALUE) || defined(TETRO_TOOLCHAIN_STATIC) || \
    defined(TOOLCHAIN_PRIVATE_STATIC)
#error An implementation dependency's definition reached its consumer.
#endif

#if __has_include("project_detail.h")
#error An implementation dependency's include path reached its consumer.
#endif

#if defined(__linux__)
// The public linker option redirects this declaration to the wrapper, proving
// that release metadata carries the consumer's required link behavior.
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
