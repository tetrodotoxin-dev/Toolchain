// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/unit_test.hpp"

#include <stdlib.h>

#include "toolchain/validation/clock.hpp"

using namespace Toolchain::Validation;

struct Instance {
  const Harness* harness;
  const char* name;
  Test::TestFunc run;
  const char* file;
  size_t line;
};

// Static registration only records borrowed declarations. Nothing from the
// library under test is needed before its first test begins.
static Instance tests[4096];
static size_t count = 0;

auto Test::create(
    const Harness& harness,
    const char* name,
    TestFunc run,
    const char* file,
    size_t line) -> void {
  if (count == sizeof(tests) / sizeof(*tests)) {
    fputs("Validation registration capacity exceeded.\n", stderr);
    abort();
  }
  tests[count++] = {&harness, name, run, file, line};
}

auto Test::log_message(Bytes file, size_t line, Bytes message) -> void {
  fwrite(file.data, 1, file.size, stdout);
  printf(":%zu:\n    ", line);
  fwrite(message.data, 1, message.size, stdout);
  fputc('\n', stdout);
}

auto Test::print_bytes(Bytes value, bool hexadecimal) -> void {
  if (!hexadecimal) {
    fwrite(value.data, 1, value.size, stdout);
    return;
  }
  const auto* data = static_cast<const unsigned char*>(value.data);
  for (size_t i = 0; i < value.size; ++i) {
    printf("%02x", unsigned(data[i]));
  }
}

auto Test::run(int argc, const char* const* argv) -> int {
  const bool silent = argc == 2 && !strcmp(argv[1], "silent");
  if (argc > 2 || (argc == 2 && !silent)) {
    fprintf(stderr, "Usage: %s [silent]\n", argv[0]);
    return 1;
  }
  size_t passed = 0;
  size_t failed = 0;
  size_t skipped = 0;
  const Harness* active = nullptr;
  const uint64_t started = time_ns();
  if (!silent) {
    printf("Tests found: %zu\n", count);
  }
  for (size_t i = 0; i < count; ++i) {
    const auto& test = tests[i];
    if (active != test.harness) {
      active = test.harness;
      if (!silent) {
        printf("[ START ] %s\n", active->name);
      }
      if (active->init) {
        active->init();
      }
    }
    if (active->setup) {
      active->setup();
    }
    TestResult result = TestResult::Pass;
    const uint64_t begin = time_ns();
    test.run(result);
    const double milliseconds = double(time_ns() - begin) / 1'000'000;
    if (active->teardown) {
      active->teardown();
    }
    const char* outcome;
    switch (result) {
    case TestResult::Pass:
      ++passed;
      outcome = "PASS";
      break;
    case TestResult::Failed:
      ++failed;
      outcome = "FAIL";
      break;
    case TestResult::Skipped:
      ++skipped;
      outcome = "SKIP";
      break;
    }
    if (!silent || result != TestResult::Pass) {
      printf("  [ %s ] %-28s (%g ms)\n", outcome, test.name, milliseconds);
    }
  }
  printf(
      "Passed: %zu  Failed: %zu  Skipped: %zu\nTotal time: %g ms\n", passed,
      failed, skipped, double(time_ns() - started) / 1'000'000);
  return failed ? 1 : 0;
}
