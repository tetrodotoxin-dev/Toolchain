// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include <stdio.h>

#include "toolchain/validation/harness.hpp"

namespace Toolchain::Validation {

class Test {
 public:
  enum class TestResult { Pass, Failed, Skipped };
  using TestFunc = void (*)(TestResult&);

  // Construction registers one test and borrows its static harness, name and
  // callback through process completion.
  Test(
      const Harness& harness,
      Bytes<> name,
      TestFunc run,
      Bytes<> file,
      U64 line);

  // Signed and unsigned values use separate overloads so their full ranges
  // reach the formatter. Decimal formatting is compiled with the runner.
  static auto print_integer(S64 value) -> void;
  static auto print_integer(U64 value) -> void;

  // Text comparisons mark each differing byte and restore the output color
  // afterward, so the next assertion starts with ordinary terminal text.
  static auto print_character(U32 byte, bool different) -> void;

  // The byte element type stays available until formatting. Text writes use the
  // supplied extent, including bytes after a zero, and hex writes use indexing
  // through the original typed pointer.
  template <typename Element>
  static auto print_bytes(Bytes<Element> value, bool hexadecimal) -> void {
    if (!hexadecimal) {
      if (value.size) {
        fwrite(value.data, 1, value.size, stdout);
      }

      return;
    }

    for (CppSize i = 0; i < value.size; ++i) {
      const U32 byte = value.data[i] & 0xff;
      printf("%02X ", byte);
    }
  }

  template <typename Left, typename Right>
  static auto print_difference(Bytes<Left> value, Bytes<Right> other) -> void {
    for (CppSize i = 0; i < value.size; ++i) {
      const U32 byte = value.data[i] & 0xff;
      const bool different = i >= other.size || byte != (other.data[i] & 0xffu);
      print_character(byte, different);
    }
  }

  template <typename File, typename Message>
  static auto log_message(Bytes<File> file, U64 line, Bytes<Message> message)
      -> void {
    print_bytes(file, false);
    printf(":%llu:\n    ", line);
    print_bytes(message, false);
    fputc('\n', stdout);
  }

  template <typename Left = char, typename Right = char>
  static auto equal_bytes(Bytes<Left> left, Bytes<Right> right) -> bool {
    return left.size == right.size &&
           (!left.size || !memcmp(left.data, right.data, left.size));
  }

  template <typename T>
  static auto expected(const T& value, bool actual) -> void {
    fputs(actual ? "    ACTUAL = " : "  EXPECTED = ", stdout);
    if constexpr (__is_enum(T)) {
      // Convert to the enum's declared integer type before promotion so its
      // signedness and range survive. The compiler query keeps this header
      // self contained.
      using Integer = __underlying_type(T);
      const auto integer = static_cast<Integer>(value);
      if constexpr (__is_signed(Integer)) {
        const S64 promoted = integer;
        print_integer(promoted);
      } else {
        const U64 promoted = integer;
        print_integer(promoted);
      }
    } else if constexpr (__is_same(T, bool)) {
      fputs(value ? "true" : "false", stdout);
    } else if constexpr (__is_integral(T)) {
      if constexpr (__is_signed(T)) {
        const S64 promoted = value;
        print_integer(promoted);
      } else {
        const U64 promoted = value;
        print_integer(promoted);
      }
    } else if constexpr (__is_floating_point(T)) {
      const R64 promoted = value;
      printf("%.17g", promoted);
    } else if constexpr (requires { bytes(value); }) {
      print_bytes(bytes(value), false);
    } else if constexpr (__is_convertible(T, const void*)) {
      const void* pointer = value;
      printf("%p", pointer);
    } else if constexpr (requires { value ? true : false; }) {
      fputs(value ? "true" : "false", stdout);
    } else {
      fputs("<value>", stdout);
    }

    fputc('\n', stdout);
  }
};

}  // namespace Toolchain::Validation

#define VALIDATION_CHECK(expression, expected_value, comparison, stop)   \
  do {                                                                   \
    auto&& validation_actual = (expression);                             \
    auto&& validation_expected = (expected_value);                       \
    if (!(validation_actual comparison validation_expected)) {           \
      Toolchain::Validation::Test::log_message(                          \
          Toolchain::Validation::bytes(__FILE__), __LINE__,              \
          Toolchain::Validation::bytes(                                  \
              #expression " " #comparison " " #expected_value));         \
      Toolchain::Validation::Test::expected(validation_expected, false); \
      Toolchain::Validation::Test::expected(validation_actual, true);    \
      result = Toolchain::Validation::Test::TestResult::Failed;          \
      if constexpr (stop)                                                \
        return;                                                          \
    }                                                                    \
  } while (false)

#define EXPECT(expression) \
  VALIDATION_CHECK((expression) ? true : false, true, ==, false)
#define ASSERT(expression) \
  VALIDATION_CHECK((expression) ? true : false, true, ==, true)
#define EXPECT_NOT(expression) \
  VALIDATION_CHECK((expression) ? true : false, false, ==, false)
#define ASSERT_NOT(expression) \
  VALIDATION_CHECK((expression) ? true : false, false, ==, true)
#define EXPECT_EQ(expression, expected_value) \
  VALIDATION_CHECK(expression, expected_value, ==, false)
#define ASSERT_EQ(expression, expected_value) \
  VALIDATION_CHECK(expression, expected_value, ==, true)
#define EXPECT_NEQ(expression, expected_value) \
  VALIDATION_CHECK(expression, expected_value, !=, false)
#define ASSERT_NEQ(expression, expected_value) \
  VALIDATION_CHECK(expression, expected_value, !=, true)

#define VALIDATION_BYTES(expression, expected_value, hexadecimal, stop)      \
  do {                                                                       \
    auto&& validation_actual_owner = (expression);                           \
    auto&& validation_expected_owner = (expected_value);                     \
    const auto validation_actual =                                           \
        Toolchain::Validation::bytes(validation_actual_owner);               \
    const auto validation_expected =                                         \
        Toolchain::Validation::bytes(validation_expected_owner);             \
    if (!Toolchain::Validation::Test::equal_bytes(                           \
            validation_actual, validation_expected)) {                       \
      Toolchain::Validation::Test::log_message(                              \
          Toolchain::Validation::bytes(__FILE__), __LINE__,                  \
          Toolchain::Validation::bytes(                                      \
              #expression " differs from " #expected_value));                \
      fputs("  EXPECTED = ", stdout);                                        \
      if constexpr (hexadecimal) {                                           \
        Toolchain::Validation::Test::print_bytes(validation_expected, true); \
      } else {                                                               \
        Toolchain::Validation::Test::print_difference(                       \
            validation_expected, validation_actual);                         \
      }                                                                      \
      fputs("\n    ACTUAL = ", stdout);                                      \
      if constexpr (hexadecimal) {                                           \
        Toolchain::Validation::Test::print_bytes(validation_actual, true);   \
      } else {                                                               \
        Toolchain::Validation::Test::print_difference(                       \
            validation_actual, validation_expected);                         \
      }                                                                      \
      fputc('\n', stdout);                                                   \
      result = Toolchain::Validation::Test::TestResult::Failed;              \
      if constexpr (stop)                                                    \
        return;                                                              \
    }                                                                        \
  } while (false)

#define EXPECT_TEXT(expression, expected_value) \
  VALIDATION_BYTES(expression, expected_value, false, false)
#define ASSERT_TEXT(expression, expected_value) \
  VALIDATION_BYTES(expression, expected_value, false, true)
#define EXPECT_HEX(expression, expected_value) \
  VALIDATION_BYTES(expression, expected_value, true, false)
#define ASSERT_HEX(expression, expected_value) \
  VALIDATION_BYTES(expression, expected_value, true, true)

#define SKIP(message)                                          \
  do {                                                         \
    Toolchain::Validation::Test::log_message(                  \
        Toolchain::Validation::bytes(__FILE__), __LINE__,      \
        Toolchain::Validation::bytes(message));                \
    result = Toolchain::Validation::Test::TestResult::Skipped; \
    return;                                                    \
  } while (false)

#define VALIDATION_TEST(harness, name)                             \
  static auto validation_test_##harness##_##name(                  \
      Toolchain::Validation::Test::TestResult& result) -> void;    \
  namespace {                                                      \
  Toolchain::Validation::Test validation_entry_##harness##_##name( \
      harness,                                                     \
      #name,                                                       \
      validation_test_##harness##_##name,                          \
      __FILE__,                                                    \
      __LINE__);                                                   \
  }                                                                \
  static auto validation_test_##harness##_##name(                  \
      Toolchain::Validation::Test::TestResult& result) -> void
