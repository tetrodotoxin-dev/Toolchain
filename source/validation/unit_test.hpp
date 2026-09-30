// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include <stdint.h>
#include <stdio.h>

#include "toolchain/validation/harness.hpp"

namespace Toolchain::Validation::Test {

enum class TestResult { Pass, Failed, Skipped };
using TestFunc = void (*)(TestResult&);

auto create(
    const Harness& harness,
    const char* name,
    TestFunc run,
    const char* file,
    uint64_t line) -> void;
auto log_message(Bytes file, uint64_t line, Bytes message) -> void;
auto print_bytes(Bytes value, bool hexadecimal) -> void;
auto run(int argc, const char* const* argv) -> int;

inline auto equal_bytes(Bytes left, Bytes right) -> bool {
  return left.size == right.size &&
         (!left.size || !memcmp(left.data, right.data, left.size));
}

template <typename T>
inline auto expected(const T& value, bool actual) -> void {
  fputs(actual ? "    ACTUAL = " : "  EXPECTED = ", stdout);
  if constexpr (__is_integral(T) || __is_enum(T)) {
    if constexpr (__is_signed(T)) {
      printf("%lld", (long long)value);
    } else {
      printf("%llu", (unsigned long long)value);
    }
  } else if constexpr (__is_floating_point(T)) {
    printf("%.17g", double(value));
  } else if constexpr (requires { bytes(value); }) {
    print_bytes(bytes(value), false);
  } else if constexpr (__is_pointer(T)) {
    printf("%p", (const void*)value);
  } else if constexpr (requires { bool(value); }) {
    fputs(bool(value) ? "true" : "false", stdout);
  } else {
    fputs("<value>", stdout);
  }
  fputc('\n', stdout);
}

class TestEntry {
 public:
  TestEntry(
      const Harness& harness,
      const char* name,
      TestFunc function,
      const char* file,
      uint64_t line) {
    create(harness, name, function, file, line);
  }
};

}  // namespace Toolchain::Validation::Test

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

#define EXPECT(expression) VALIDATION_CHECK(bool(expression), true, ==, false)
#define ASSERT(expression) VALIDATION_CHECK(bool(expression), true, ==, true)
#define EXPECT_NOT(expression) \
  VALIDATION_CHECK(bool(expression), false, ==, false)
#define ASSERT_NOT(expression) \
  VALIDATION_CHECK(bool(expression), false, ==, true)
#define EXPECT_EQ(expression, expected_value) \
  VALIDATION_CHECK(expression, expected_value, ==, false)
#define ASSERT_EQ(expression, expected_value) \
  VALIDATION_CHECK(expression, expected_value, ==, true)
#define EXPECT_NEQ(expression, expected_value) \
  VALIDATION_CHECK(expression, expected_value, !=, false)
#define ASSERT_NEQ(expression, expected_value) \
  VALIDATION_CHECK(expression, expected_value, !=, true)

#define VALIDATION_BYTES(expression, expected_value, hexadecimal, stop) \
  do {                                                                  \
    auto&& validation_actual_owner = (expression);                      \
    auto&& validation_expected_owner = (expected_value);                \
    const auto validation_actual =                                      \
        Toolchain::Validation::bytes(validation_actual_owner);          \
    const auto validation_expected =                                    \
        Toolchain::Validation::bytes(validation_expected_owner);        \
    if (!Toolchain::Validation::Test::equal_bytes(                      \
            validation_actual, validation_expected)) {                  \
      Toolchain::Validation::Test::log_message(                         \
          Toolchain::Validation::bytes(__FILE__), __LINE__,             \
          Toolchain::Validation::bytes(                                 \
              #expression " differs from " #expected_value));           \
      fputs("  EXPECTED = ", stdout);                                   \
      Toolchain::Validation::Test::print_bytes(                         \
          validation_expected, hexadecimal);                            \
      fputs("\n    ACTUAL = ", stdout);                                 \
      Toolchain::Validation::Test::print_bytes(                         \
          validation_actual, hexadecimal);                              \
      fputc('\n', stdout);                                              \
      result = Toolchain::Validation::Test::TestResult::Failed;         \
      if constexpr (stop)                                               \
        return;                                                         \
    }                                                                   \
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

#define VALIDATION_TEST(harness, name)                                        \
  static auto validation_test_##harness##_##name(                             \
      Toolchain::Validation::Test::TestResult& result) -> void;               \
  namespace {                                                                 \
  Toolchain::Validation::Test::TestEntry validation_entry_##harness##_##name( \
      harness,                                                                \
      #name,                                                                  \
      validation_test_##harness##_##name,                                     \
      __FILE__,                                                               \
      __LINE__);                                                              \
  }                                                                           \
  static auto validation_test_##harness##_##name(                             \
      Toolchain::Validation::Test::TestResult& result) -> void
