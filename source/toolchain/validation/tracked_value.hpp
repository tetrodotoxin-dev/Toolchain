// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/toolchain.hpp"

namespace Toolchain::Validation {

// TrackedValue counts each current object from construction through
// destruction. Copy and move construction retain the same counter record so a
// test can compare the number of created and destroyed objects after every
// temporary and stored value leaves scope. Assignment is disabled because it
// does not begin or end an object lifetime.
template <typename value_type>
class TrackedValue {
 public:
  struct Counts {
    U64 constructions = 0;
    U64 destructions = 0;
  };

  constexpr TrackedValue(value_type value, Counts& counts)
      : value(value), counts(&counts) {
    counts.constructions++;
  }

  constexpr TrackedValue(const TrackedValue& source)
      : value(source.value), counts(source.counts) {
    counts->constructions++;
  }

  constexpr TrackedValue(TrackedValue&& source)
      : value(source.value), counts(source.counts) {
    counts->constructions++;
  }

  constexpr ~TrackedValue() { counts->destructions++; }

  auto operator=(const TrackedValue&) -> TrackedValue& = delete;
  auto operator=(TrackedValue&&) -> TrackedValue& = delete;

  constexpr auto get_value() const -> value_type { return value; }
  constexpr auto operator==(const TrackedValue& rhs) const -> bool {
    return value == rhs.value;
  }

 private:
  value_type value;
  Counts* counts;
};

}  // namespace Toolchain::Validation
