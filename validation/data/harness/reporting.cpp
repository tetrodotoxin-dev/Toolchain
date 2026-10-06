// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include <chrono>
#include <thread>

#include "toolchain/validation/test.hpp"

using namespace Toolchain::Validation;

enum class SmallEnum : int8_t { Zero, Negative = -7 };
enum class SignedEnum : int64_t { Zero, Minimum = INT64_MIN };
enum class UnsignedEnum : uint64_t { Zero, Maximum = UINT64_MAX };

// A range of words has the same accessors as a byte range. Comparability is
// sufficient for EXPECT_EQ, while the diagnostic uses its generic value form.
template <typename Element>
struct Range {
  const Element* data;
  size_t size;

  auto get_data() const -> const Element* { return data; }
  auto get_size() const -> size_t { return size; }
  auto operator==(const Range&) const -> bool = default;
};

template <typename Element>
struct Buffer {
  Range<Element> view;

  auto get_view() const -> Range<Element> { return view; }
  auto operator==(const Buffer&) const -> bool = default;
};

// The process checker observes destruction after main returns. The fixture
// records whether failed and skipped bodies still receive their teardown.
struct Fixture {
  unsigned setups = 0;
  unsigned teardowns = 0;

  Fixture() { puts("report fixture constructed"); }
  ~Fixture() {
    printf(
        "report fixture destroyed: setup=%u teardown=%u\n", setups, teardowns);
  }
};

static Fixture fixture;
static Harness Reporting = {
  .name = "Reporting",
  .setup = [] { ++fixture.setups; },
  .teardown = [] { ++fixture.teardowns; },
};

VALIDATION_TEST(Reporting, slow_pass) {
  // Exercise the real clock with enough margin to pass the one second warning
  // threshold. The checker asserts the warning while accepting the measured
  // duration supplied by the host clock.
  std::this_thread::sleep_for(std::chrono::milliseconds(1100));
  EXPECT(true);
}

VALIDATION_TEST(Reporting, failure) {
  EXPECT_EQ(false, true);
  EXPECT_EQ(1.25f, 0.0f);
  EXPECT_EQ(-2.5, 0.0);
  const int8_t small = -128;
  const uint64_t large = UINT64_MAX;
  EXPECT_EQ(small, 0);
  EXPECT_EQ(large, 0u);
  EXPECT_EQ(SmallEnum::Negative, SmallEnum::Zero);
  EXPECT_EQ(SignedEnum::Minimum, SignedEnum::Zero);
  EXPECT_EQ(UnsignedEnum::Maximum, UnsignedEnum::Zero);
  const signed char actual[] = {0, 127, -1};
  const unsigned char expected[] = {0, 127, 0};
  EXPECT_HEX(
      (Bytes{actual, sizeof(actual)}), (Bytes{expected, sizeof(expected)}));
  EXPECT_TEXT("aXc!", "abc");
  EXPECT_TEXT("a\0X", "a\0b");
  const unsigned words[] = {1, 2};
  const Range<unsigned> range = {words, 2};
  EXPECT_EQ(range, (Range<unsigned>{words, 1}));
  EXPECT_EQ((Buffer<unsigned>{range}), (Buffer<unsigned>{{words, 1}}));
  const Buffer<char> text = {{"range", 5}};
  EXPECT_EQ(text, (Buffer<char>{{"other", 5}}));
  puts("continued after EXPECT");
}

VALIDATION_TEST(Reporting, assertion) {
  ASSERT_EQ(1, 2);
  puts("unreachable after ASSERT");
}

VALIDATION_TEST(Reporting, skipped) {
  SKIP("example skip");
  puts("unreachable after SKIP");
}
