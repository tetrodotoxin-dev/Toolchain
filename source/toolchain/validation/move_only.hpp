// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.hpp"

namespace Toolchain::Validation {

// MoveOnly lets validation code prove that an operation transfers a value
// through construction without relying on a project type. The source resets to
// its default value after construction. Copying and assignment remain disabled
// so an implementation cannot satisfy the test through another operation.
template <typename value_type>
class MoveOnly {
 public:
  constexpr MoveOnly() = default;

  // Explicit construction prevents a payload from silently becoming a fixture
  // when the operation under test also accepts the payload type.
  constexpr explicit MoveOnly(value_type value) : value(value) {}

  MoveOnly(const MoveOnly&) = delete;
  constexpr MoveOnly(MoveOnly&& source) : value(source.value) {
    source.value = value_type();
  }

  auto operator=(const MoveOnly&) -> MoveOnly& = delete;
  auto operator=(MoveOnly&&) -> MoveOnly& = delete;

  constexpr auto get_value() const -> value_type { return value; }
  constexpr auto operator==(const MoveOnly& rhs) const -> bool {
    return value == rhs.value;
  }

 private:
  value_type value = value_type();
};

}  // namespace Toolchain::Validation
