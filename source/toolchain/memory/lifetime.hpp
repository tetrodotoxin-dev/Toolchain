// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

// C++26 placement new expressions still require explicit declarations. Native
// declarations match the pinned libraries so either include order is valid.
// Including <new> here would add its C++ dependencies to every translation
// unit using a core container which bloats compile times by over a minute.
#ifdef TOOLCHAIN_WASM

// Pinned Web libc++ groups all four placement operations under this guard.
// Supply the complete group so later standard headers retain their remaining
// declarations without adding incompatible ABI attributes to these functions.
#ifndef _LIBCPP___NEW_PLACEMENT_NEW_DELETE_H
#define _LIBCPP___NEW_PLACEMENT_NEW_DELETE_H

constexpr auto operator new(CppSize, void* address) noexcept -> void* {
  return address;
}

constexpr auto operator new[](CppSize, void* address) noexcept -> void* {
  return address;
}

inline auto operator delete(void*, void*) noexcept -> void {}
inline auto operator delete[](void*, void*) noexcept -> void {}

#endif

#else

auto operator new(CppSize, void*) noexcept -> void*;
auto operator delete(void*, void*) noexcept -> void;

#endif

namespace Toolchain::Memory {

// Lifetime begins an object inside storage managed by its caller. The factory
// is consumed exactly once and its result uses guaranteed elision into that
// address.
class Lifetime {
 public:
  template <typename Type, typename Factory>
  __attribute__((always_inline)) static constexpr auto construct(
      void* address,
      Factory create) -> Type& {
    return *new (address) Type(create());
  }

  template <typename Type>
  __attribute__((always_inline)) static constexpr auto construct(void* address)
      -> Type& {
    return *new (address) Type();
  }
};

}  // namespace Toolchain::Memory
