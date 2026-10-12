// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.h"

namespace Toolchain::Memory {

// ConstAllocation owns an array that exists only during constant evaluation.
// Its immediate construction prevents the allocated address from escaping into
// runtime code. Destruction remains constexpr because C++ destroys constant
// values through the ordinary destructor language rule.
template <typename Type>
class ConstAllocation {
 public:
  consteval ConstAllocation() = default;
  // A Count must not silently acquire storage ownership. Explicit construction
  // makes allocation visible at the call site.
  consteval explicit ConstAllocation(Count capacity)
      : data(capacity ? new Type[capacity]{} : nullptr), capacity(capacity) {}

  ConstAllocation(const ConstAllocation&) = delete;
  consteval ConstAllocation(ConstAllocation&& other) { take(other); }

  constexpr ~ConstAllocation() { delete[] data; }

  auto operator=(const ConstAllocation&) -> ConstAllocation& = delete;
  consteval auto operator=(ConstAllocation&& other) -> ConstAllocation& {
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
  consteval auto take(ConstAllocation& other) -> void {
    data = other.data;
    capacity = other.capacity;
    other.data = nullptr;
    other.capacity = 0;
  }

  Type* data = nullptr;
  Count capacity = 0;
};

}  // namespace Toolchain::Memory
