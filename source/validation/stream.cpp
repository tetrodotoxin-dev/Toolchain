// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/stream.hpp"

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#endif

using namespace Toolchain::Validation;

#ifdef _WIN32
// The CRT takes ownership only after conversion succeeds. Closing the native
// handle on failure also removes a temporary file marked for deletion.
static auto stream_from_handle(HANDLE handle) -> FILE* {
  if (handle == INVALID_HANDLE_VALUE) {
    return nullptr;
  }

  int descriptor =
      _open_osfhandle(reinterpret_cast<intptr_t>(handle), _O_RDWR | _O_BINARY);
  if (descriptor < 0) {
    CloseHandle(handle);
    return nullptr;
  }

  FILE* stream = _fdopen(descriptor, "w+b");
  if (!stream) {
    _close(descriptor);
  }

  return stream;
}
#endif

auto Toolchain::Validation::temporary_stream() -> FILE* {
#ifdef _WIN32
  // Microsoft's tmpfile uses the drive root, which an ordinary user may not
  // write. Ask Windows for its temporary directory instead.
  wchar_t directory[MAX_PATH];
  wchar_t path[MAX_PATH];
  const DWORD size = GetTempPathW(MAX_PATH, directory);
  if (!size || size >= MAX_PATH ||
      !GetTempFileNameW(directory, L"ttx", 0, path)) {
    return nullptr;
  }

  HANDLE handle = CreateFileW(
      path, GENERIC_READ | GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE,
      nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    DeleteFileW(path);
  }

  return stream_from_handle(handle);
#else
  return tmpfile();
#endif
}

auto Toolchain::Validation::failing_stream() -> FILE* {
#ifdef _WIN32
  // The stream permits output, but its native handle has no write access.
  // This reaches the real CRT write failure without a full disk fixture.
  return stream_from_handle(CreateFileW(
      L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
      OPEN_EXISTING, 0, nullptr));
#else
  return fopen("/dev/full", "wb");
#endif
}
