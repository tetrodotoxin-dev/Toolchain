// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include <stddef.h>
#include <string.h>

namespace Toolchain::Validation {

// Validation borrows bytes from the caller. Keeping the element type lets
// hexadecimal reporting read those bytes through their original pointer.
// Explicit ranges include every byte, including embedded zeros. A terminated
// character array lends the elements preceding its terminator.
template <typename Element = char>
  requires(__is_integral(Element) && sizeof(Element) == 1)
struct Bytes {
  const Element* data = nullptr;
  size_t size = 0;

  constexpr Bytes() = default;
  constexpr Bytes(const Element* data, size_t size) : data(data), size(size) {}

  template <size_t Size>
    requires(__is_same(Element, char))
  constexpr Bytes(const Element (&text)[Size])
      : data(text), size(Size - (text[Size - 1] == 0)) {}
};

// The caller supplies a readable extent. Scanning stops at its first zero or
// at that extent, so an unterminated buffer lends exactly the supplied range.
constexpr auto convert_cstring(const char* text, size_t capacity) -> Bytes<> {
  size_t size = 0;
  while (size < capacity && text[size]) {
    ++size;
  }
  return {text, size};
}

template <size_t Size>
constexpr auto bytes(const char (&text)[Size]) -> Bytes<> {
  return {text};
}

template <typename Element>
constexpr auto bytes(Bytes<Element> value) -> Bytes<Element> {
  return value;
}

// Assertion formatting borrows a contiguous byte observation. These overloads
// accept a caller's byte view while keeping the runner independent of its type.
// Wider elements use the ordinary value fallback.
template <typename T>
  requires requires(const T& value, size_t size) {
    Bytes{value.get_data(), size};
    size = value.get_size();
  }
inline auto bytes(const T& value) {
  const size_t size = value.get_size();
  return Bytes{value.get_data(), size};
}

template <typename T>
  requires(!requires(const T& value) {
            value.get_data();
            value.get_size();
          }) && requires(const T& value) { value.get_view(); }
inline auto bytes(const T& value) -> decltype(bytes(value.get_view())) {
  return bytes(value.get_view());
}

// Registration borrows static names and callbacks. Keeping this record free of
// project types lets the runner test a library whose allocator or logging is
// itself under investigation.
struct Harness {
  Bytes<> name;
  void (*init)() = nullptr;
  void (*setup)() = nullptr;
  void (*teardown)() = nullptr;
};

}  // namespace Toolchain::Validation
