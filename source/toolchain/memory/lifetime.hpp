// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

// C++26 recognizes these standard placement operations during constant
// evaluation but they require an explicit declaration. Since the Tetrodotoxin
// family of projects avoid using C++ headers in favor of a more compact C
// header surface this is the only way to get access to placement new without
// including `<new>` which is an interesting standards choice.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundefined-inline"

constexpr auto operator new(CppSize, void*) noexcept -> void*;
constexpr auto operator delete(void*, void*) noexcept -> void;

#pragma clang diagnostic pop

namespace Toolchain::Memory {

// Lifetime begins an object inside storage managed by its caller. A factory
// preserves value category and uses guaranteed elision into that address.
class Lifetime {
 public:
  template <typename Type, typename Factory>
  __attribute__((always_inline)) static constexpr auto construct(
      void* address,
      Factory&& create) -> Type&;

  template <typename Type>
  __attribute__((always_inline)) static constexpr auto construct(void* address)
      -> Type&;
};

}  // namespace Toolchain::Memory

template <typename Type, typename Factory>
__attribute__((always_inline)) constexpr auto
    Toolchain::Memory::Lifetime::construct(void* address, Factory&& create)
        -> Type& {
  return *new (address) Type(static_cast<Factory&&>(create)());
}

template <typename Type>
__attribute__((always_inline)) constexpr auto
    Toolchain::Memory::Lifetime::construct(void* address) -> Type& {
  return *new (address) Type();
}
