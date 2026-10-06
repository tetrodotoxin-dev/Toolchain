// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/test.hpp"

using namespace Toolchain::Validation;

// Construction and destruction messages let the external checker verify the
// ordinary executable lifecycle, including cleanup after its final test.
struct Fixture {
  unsigned initializations = 0;
  unsigned setups = 0;
  unsigned teardowns = 0;
  int value = -1;

  Fixture() { puts("test fixture constructed"); }
  ~Fixture() {
    printf(
        "test fixture destroyed: init=%u setup=%u teardown=%u value=%d\n",
        initializations, setups, teardowns, value);
  }
};

static Fixture fixture;
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
  int expected = 0;
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
  const unsigned char unsigned_bytes[] = {0, 127, 255};
  const signed char signed_bytes[] = {0, 127, -1};
  EXPECT_HEX(
      (Bytes{unsigned_bytes, sizeof(unsigned_bytes)}),
      (Bytes{signed_bytes, sizeof(signed_bytes)}));
}
