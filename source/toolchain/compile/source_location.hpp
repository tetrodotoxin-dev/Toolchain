// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

// Compiler extension ABI

namespace std {

class source_location {
 public:
  struct __impl {
    const char* _M_file_name;
    const char* _M_function_name;
    U32 _M_line;
    U32 _M_column;
  };
};

}  // namespace std

namespace Toolchain::Compile {

// SourceLocation isolates the compiler source location builtin and its record
// layout. Toolchain projects can therefore capture callers during constant
// evaluation while sharing one compiler ABI. File and function pointers refer
// to read only program storage, but carry no extent or encoding promise.
// Consumers establish those string boundaries before publishing the location
// through their own interfaces.
class SourceLocation {
 public:
  // The default argument is evaluated at the caller and records that location
  // in read only program storage.
  static consteval auto current(
      const std::source_location::__impl* location =
          __builtin_source_location()) -> SourceLocation {
    return SourceLocation(location);
  }

  constexpr SourceLocation() = default;

  constexpr auto is_set() const -> bool { return location != nullptr; }
  constexpr auto get_line() const -> U32 {
    return location ? location->_M_line : 0;
  }

  constexpr auto get_column() const -> U32 {
    return location ? location->_M_column : 0;
  }

  constexpr auto get_file() const -> const char* {
    return location ? location->_M_file_name : nullptr;
  }

  constexpr auto get_function() const -> const char* {
    return location ? location->_M_function_name : nullptr;
  }

 private:
  constexpr SourceLocation(const std::source_location::__impl* selected)
      : location(selected) {}

  const std::source_location::__impl* location = nullptr;
};

static_assert(sizeof(SourceLocation) == sizeof(void*));

}  // namespace Toolchain::Compile
