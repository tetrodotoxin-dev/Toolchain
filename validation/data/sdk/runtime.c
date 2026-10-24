// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/runtime.h"

#if defined(TOOLCHAIN_LINUX) || defined(TOOLCHAIN_WINDOWS)
#include "validation/data/sdk/host.h"
#endif

static S32 initialized = 0;

C_LINKAGE HIDDEN void toolchain_runtime_initialize(void) {
  initialized = 1;
}

#if defined(__linux__)

// This reference requires the archive's linker option at the final link.
S32 toolchain_archive_probe(void);

S32 __wrap_toolchain_archive_probe(void) {
  return initialized;
}

#endif

C_LINKAGE S32 toolchain_runtime_entry(S32 value) {

#if defined(TOOLCHAIN_LINUX) || defined(TOOLCHAIN_WINDOWS)

  value = toolchain_host_entry(value);

#endif

#if defined(__linux__)

  return toolchain_archive_probe() ? value : -1;

#else

  return initialized ? value : -1;

#endif
}
