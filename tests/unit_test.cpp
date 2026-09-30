// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/unit_test.hpp"

using namespace Toolchain::Validation;

static Harness Assertions = {.name = "Validation::Assertions"};

VALIDATION_TEST(Assertions, evaluates_each_operand_once) {
  int actual = 0;
  int expected = 0;
  EXPECT_EQ(++actual, ++expected);
  ASSERT_EQ(actual, 1);
  ASSERT_EQ(expected, 1);
}

VALIDATION_TEST(Assertions, compares_complete_byte_ranges) {
  const char left[] = {'a', 0, 'b'};
  const char same[] = {'a', 0, 'b'};
  const char different[] = {'a', 0, 'c'};
  const Bytes value = {left, sizeof(left)};
  EXPECT_HEX(value, (Bytes{same, sizeof(same)}));
  EXPECT_NOT(Test::equal_bytes(value, {different, sizeof(different)}));
  EXPECT_NOT(Test::equal_bytes(value, {left, sizeof(left) - 1}));
  EXPECT(Test::equal_bytes({}, {}));
}
