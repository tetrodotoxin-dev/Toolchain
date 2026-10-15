// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

namespace Toolchain::Compile {

// Allocation owns a value initialized array that exists only during constant
// evaluation. Immediate construction prevents its address from escaping into
// runtime code. Destruction remains constexpr because C++ destroys constant
// values through the ordinary destructor language rule.
template <typename Type>
class Allocation {
 public:
  consteval Allocation() = default;
  // A Count must not silently acquire storage ownership. Explicit construction
  // makes allocation visible at the call site.
  consteval explicit Allocation(Count capacity)
      : data(capacity ? new Type[capacity]{} : nullptr), capacity(capacity) {}

  Allocation(const Allocation&) = delete;
  consteval Allocation(Allocation&& other) { take(other); }

  constexpr ~Allocation() { delete[] data; }

  auto operator=(const Allocation&) -> Allocation& = delete;
  consteval auto operator=(Allocation&& other) -> Allocation& {
    if (this != &other) {
      delete[] data;
      data = nullptr;
      capacity = 0;
      take(other);
    }

    return *this;
  }

  constexpr auto get_data() const -> const Type* { return data; }
  constexpr auto get_data() -> Type* { return data; }
  constexpr auto get_capacity() const -> Count { return capacity; }

 private:
  consteval auto take(Allocation& other) -> void {
    data = other.data;
    capacity = other.capacity;
    other.data = nullptr;
    other.capacity = 0;
  }

  Type* data = nullptr;
  Count capacity = 0;
};

}  // namespace Toolchain::Compile
