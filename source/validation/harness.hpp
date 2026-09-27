// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include <stddef.h>
#include <string.h>

namespace Toolchain::Validation {

// Registration borrows static names and callbacks. Keeping this record free of
// project types lets the runner test a library whose allocator or logging is
// itself under investigation.
struct Harness {
  const char* name;
  void (*init)() = nullptr;
  void (*setup)() = nullptr;
  void (*teardown)() = nullptr;
};

struct Bytes {
  const void* data;
  size_t size;
};

inline auto bytes(const char* text) -> Bytes {
  return {text, text ? strlen(text) : 0};
}

inline auto bytes(Bytes value) -> Bytes {
  return value;
}

// Assertion formatting borrows a contiguous byte observation. These overloads
// accept a caller's view without making the runner depend on its owner.
template <typename T>
  requires requires(const T& value) {
    value.get_data();
    value.get_size();
  }
inline auto bytes(const T& value) -> Bytes {
  static_assert(sizeof(*value.get_data()) == 1);
  return {value.get_data(), size_t(value.get_size())};
}

template <typename T>
  requires(!requires(const T& value) {
            value.get_data();
            value.get_size();
          }) && requires(const T& value) { value.get_view(); }
inline auto bytes(const T& value) -> Bytes {
  return bytes(value.get_view());
}

}  // namespace Toolchain::Validation
