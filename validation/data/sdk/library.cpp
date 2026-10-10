// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/library.h"

#include "toolchain/toolchain.hpp"

using namespace Toolchain::Memory;

struct Fixture {
  S32 value;
};

union FixtureStorage {
  Fixture value;
  constexpr FixtureStorage() {}
};

static_assert([] {
  FixtureStorage storage;
  return Lifetime::construct<Fixture>(&storage.value).value == 0;
}());

static_assert([] {
  FixtureStorage storage;
  Lifetime::construct<Fixture>(&storage.value, [] { return Fixture{42}; });
  return storage.value.value == 42;
}());

// The C++ helper keeps native linkage. The entrypoint has C linkage and an
// independent export annotation for hosts that discover it by name.
HIDDEN auto toolchain_cpp_helper(S32 value) -> S32 {
  alignas(Fixture) U8 storage[sizeof(Fixture)];

  Fixture& fixture = Lifetime::construct<Fixture>(
      storage, [value] { return Fixture{S32(value * 2)}; });
  return fixture.value;
}

C_LINKAGE auto toolchain_cpp_entry(S32 value) -> S32 {
  return toolchain_cpp_helper(value);
}
