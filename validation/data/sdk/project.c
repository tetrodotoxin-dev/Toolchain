// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/project.h"

#include "validation/data/sdk/runtime.h"

#if defined(_WIN32)
#include <windows.h>
#endif

#ifdef TOOLCHAIN_TEST_EXPORT
#error A dependent library's export flag reached this implementation.
#endif

C_LINKAGE S32 toolchain_project_entry(S32 value) {

#if defined(_WIN32)

  // Loading the module exercises runtime packaging independently of
  // the linked runtime's import library. The provider retains the DLL through
  // the call and releases it after the returned function finishes.
  HMODULE module = LoadLibraryW(L"plugin.dll");
  if (!module) {
    return -1;
  }

  typedef S32 (*entry_function)(S32);
  entry_function entry =
      (entry_function)GetProcAddress(module, "toolchain_plugin_entry");
  S32 result = entry ? entry(toolchain_runtime_entry(value)) : -1;
  FreeLibrary(module);
  return result;

#else

  return toolchain_runtime_entry(value);

#endif
}
