// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <time.h>
#endif

#include "toolchain/validation/test.hpp"

using namespace Toolchain::Validation;

enum class SmallEnum : S8 { Zero, Negative = -7 };
enum class SignedEnum : S64 {
  Zero,
  Minimum = S64(-9223372036854775807LL - 1),
};
enum class UnsignedEnum : U64 { Zero, Maximum = U64(-1) };

// A range of words has the same accessors as a byte range. Comparability is
// sufficient for EXPECT_EQ, while the diagnostic uses its generic value form.
template <typename Element>
struct Range {
  const Element* data;
  CppSize size;

  auto get_data() const -> const Element* { return data; }
  auto get_size() const -> CppSize { return size; }
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
  U32 setups = 0;
  U32 teardowns = 0;

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

static auto wait_for_warning_threshold() -> void {

#ifdef _WIN32

  Sleep(1100);

#else

  timespec remaining = {.tv_sec = 1, .tv_nsec = 100'000'000};
  while (nanosleep(&remaining, &remaining) != 0 && errno == EINTR) {
  }

#endif
}

VALIDATION_TEST(Reporting, slow_pass) {
  // Exercise the real clock with enough margin to pass the one second warning
  // threshold. The checker asserts the warning while accepting the measured
  // duration supplied by the host clock.
  wait_for_warning_threshold();
  EXPECT(true);
}

VALIDATION_TEST(Reporting, failure) {
  EXPECT_EQ(false, true);
  EXPECT_EQ(1.25f, 0.0f);
  EXPECT_EQ(-2.5, 0.0);

  const S8 small = -128;
  const U64 large = U64(-1);
  EXPECT_EQ(small, 0);
  EXPECT_EQ(large, 0u);
  EXPECT_EQ(SmallEnum::Negative, SmallEnum::Zero);
  EXPECT_EQ(SignedEnum::Minimum, SignedEnum::Zero);
  EXPECT_EQ(UnsignedEnum::Maximum, UnsignedEnum::Zero);

  const S8 actual[] = {0, 127, -1};
  const U8 expected[] = {0, 127, 0};
  EXPECT_HEX(
      (Bytes{actual, sizeof(actual)}), (Bytes{expected, sizeof(expected)}));
  EXPECT_TEXT("aXc!", "abc");
  EXPECT_TEXT("a\0X", "a\0b");

  const U32 words[] = {1, 2};
  const Range<U32> range = {words, 2};
  EXPECT_EQ(range, (Range<U32>{words, 1}));
  EXPECT_EQ((Buffer<U32>{range}), (Buffer<U32>{{words, 1}}));

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
