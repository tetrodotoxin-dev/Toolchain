// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/sdk/library.h"

#include "toolchain/compile/allocation.hpp"
#include "toolchain/compile/source_location.hpp"
#include "toolchain/memory/lifetime.hpp"
#include "toolchain/toolchain.hpp"

using namespace Toolchain::Compile;
using namespace Toolchain::Memory;

struct SdkFixture {
  S32 value;
};

union FixtureStorage {
  SdkFixture value;
  constexpr FixtureStorage() {}
};

static_assert([] {
  FixtureStorage storage;
  return Lifetime::construct<SdkFixture>(&storage.value).value == 0;
}());

static_assert([] {
  FixtureStorage storage;
  Lifetime::construct<SdkFixture>(
      &storage.value, [] { return SdkFixture{42}; });
  return storage.value.value == 42;
}());

static_assert([] {
  Allocation<SdkFixture> values(2);
  values.get_data()[1].value = 42;
  return values.get_data()[0].value == 0 && values.get_data()[1].value == 42;
}());

static_assert(SourceLocation::current().is_set());

// The native helper remains a private C++ symbol while the header publishes
// the C entrypoint. Exercising both in one translation unit proves export
// annotations preserve implementation privacy.
HIDDEN auto toolchain_cpp_helper(S32 value) -> S32 {
  alignas(SdkFixture) U8 storage[sizeof(SdkFixture)];

  SdkFixture& fixture = Lifetime::construct<SdkFixture>(
      storage, [value] { return SdkFixture{S32(value * 2)}; });
  return fixture.value;
}

C_LINKAGE auto toolchain_cpp_entry(S32 value) -> S32 {
  return toolchain_cpp_helper(value);
}
