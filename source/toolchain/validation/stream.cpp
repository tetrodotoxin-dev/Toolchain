// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/stream.hpp"

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <share.h>
#include <sys/stat.h>
#include <windows.h>
#endif

using namespace Toolchain::Validation;

#ifdef _WIN32
// The FILE takes ownership of the descriptor on success. Closing it on failure
// also removes a temporary file opened with the CRT's delete on close flag.
static auto stream_from_descriptor(int descriptor) -> FILE* {
  if (descriptor < 0) {
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

  int descriptor = -1;
  if (_wsopen_s(
          &descriptor, path,
          _O_RDWR | _O_BINARY | _O_TEMPORARY | _O_SHORT_LIVED, _SH_DENYRW,
          _S_IREAD | _S_IWRITE)) {
    DeleteFileW(path);
  }

  return stream_from_descriptor(descriptor);
#else
  return tmpfile();
#endif
}

auto Toolchain::Validation::failing_stream() -> FILE* {
#ifdef _WIN32
  // The stream permits output, but its native handle has no write access.
  // This reaches the real CRT write failure without a full disk fixture.
  int descriptor = -1;
  if (_wsopen_s(&descriptor, L"NUL", _O_RDONLY | _O_BINARY, _SH_DENYNO, 0)) {
    return nullptr;
  }
  return stream_from_descriptor(descriptor);
#else
  return fopen("/dev/full", "wb");
#endif
}
