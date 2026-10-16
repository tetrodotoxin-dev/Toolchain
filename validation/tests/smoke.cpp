// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/move_only.hpp"
#include "toolchain/validation/test.hpp"
#include "toolchain/validation/tracked_value.hpp"

using namespace Toolchain::Validation;

static_assert(__is_constructible(MoveOnly<U32>, MoveOnly<U32>&&));
static_assert(!__is_constructible(MoveOnly<U32>, const MoveOnly<U32>&));
static_assert(!__is_assignable(MoveOnly<U32>&, MoveOnly<U32>&&));

// Construction and destruction messages let the external checker verify the
// ordinary executable lifecycle, including cleanup after its final test.
struct TestFixture {
  U32 initializations = 0;
  U32 setups = 0;
  U32 teardowns = 0;
  S32 value = -1;

  TestFixture() { puts("test fixture constructed"); }
  ~TestFixture() {
    printf(
        "test fixture destroyed: init=%u setup=%u teardown=%u value=%d\n",
        initializations, setups, teardowns, value);
  }
};

static TestFixture fixture;
static Harness Assertions = {
  .name = "Validation::Assertions",
  .init = [] { ++fixture.initializations; },
  .setup =
      [] {
        fixture.value = 0;
        ++fixture.setups;
      },

  .teardown =
      [] {
        fixture.value = -1;
        ++fixture.teardowns;
      },
};

VALIDATION_TEST(Assertions, single_evaluation) {
  ASSERT_EQ(fixture.initializations, 1u);
  ASSERT_EQ(fixture.setups, fixture.teardowns + 1);
  ASSERT_EQ(fixture.value, 0);

  auto& actual = fixture.value;
  S32 expected = 0;
  EXPECT_EQ(++actual, ++expected);
  ASSERT_EQ(actual, 1);
  ASSERT_EQ(expected, 1);
}

VALIDATION_TEST(Assertions, byte_ranges) {
  const char left[] = {'a', 0, 'b'};
  const char same[] = {'a', 0, 'b'};
  const char different[] = {'a', 0, 'c'};
  const Bytes value = {left, sizeof(left)};
  EXPECT_HEX(value, (Bytes{same, sizeof(same)}));
  EXPECT_NOT(Test::equal_bytes(value, {different, sizeof(different)}));
  EXPECT_NOT(Test::equal_bytes(value, {left, sizeof(left) - 1}));
  EXPECT(Test::equal_bytes({}, {}));
}

VALIDATION_TEST(Assertions, bounded_strings) {
  const char text[] = {'a', 'b', 0, 'c'};
  const char unterminated[] = {'a', 'b', 'c'};
  EXPECT_TEXT(convert_cstring(text, sizeof(text)), "ab");
  EXPECT_TEXT(convert_cstring(text, 1), "a");
  EXPECT_TEXT(convert_cstring(unterminated, sizeof(unterminated)), "abc");
  EXPECT(Test::equal_bytes(convert_cstring(nullptr, 0), {}));

  const char embedded[] = {'a', 0, 'b'};
  EXPECT_HEX(bytes("a\0b"), (Bytes{embedded, sizeof(embedded)}));
}

VALIDATION_TEST(Assertions, byte_types) {
  const U8 unsigned_bytes[] = {0, 127, 255};
  const S8 signed_bytes[] = {0, 127, -1};
  EXPECT_HEX(
      (Bytes{unsigned_bytes, sizeof(unsigned_bytes)}),
      (Bytes{signed_bytes, sizeof(signed_bytes)}));
}

VALIDATION_TEST(Assertions, tracked_values) {
  TrackedValue<U32>::Counts counts;
  {
    TrackedValue<U32> first(42, counts);
    TrackedValue<U32> second(first);

    EXPECT_EQ(first.get_value(), U32(42));
    EXPECT_EQ(second.get_value(), U32(42));
    EXPECT_EQ(counts.constructions, U64(2));
    EXPECT_EQ(counts.destructions, U64(0));
  }

  EXPECT_EQ(counts.constructions, counts.destructions);
}
