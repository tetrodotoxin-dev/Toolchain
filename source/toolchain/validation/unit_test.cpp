// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/unit_test.hpp"

#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>

#include "toolchain/validation/clock.hpp"

using namespace Toolchain::Validation;

static const char* clear_color = getenv("NO_COLOR") ? "" : "\x1b[0m";
static const char* heading_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;124m";
static const char* dim_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;246m";
static const char* pass_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;34m";
static const char* fail_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;160m";
static const char* skip_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;178m";

struct Instance {
  const Harness* harness;
  Bytes<> name;
  Test::TestFunc run;
  Bytes<> file;
  uint64_t line;
  Test::TestResult result = Test::TestResult::Pass;
  double milliseconds = 0;
};

// Keep the warning threshold in milliseconds to match the reported test time.
// A slow test still has its ordinary pass, fail or skip result.
static constexpr double slow_test_ms = 1000;

// Static registration allows for easily adding tests without requiring global
// static clean up. 4k cases should be more than enough for any realistic test
// suite but the number can always be expanded if required.
// Every field is initialized before registration in other translation units.
// constinit catches a member that would reset those registrations at startup.
static constinit Instance tests[4096] = {};
static uint64_t count = 0;

// Setup the tests in registration order, but log an error and abort if we hit
// the test limit.
auto Test::create(
    const Harness& harness,
    Bytes<> name,
    TestFunc run,
    Bytes<> file,
    uint64_t line) -> void {
  if (count == sizeof(tests) / sizeof(*tests)) {
    fputs(
        "Validation registration capacity exceeded the 4096 test limit.\n",
        stderr);
    abort();
  }

  tests[count++] = {&harness, name, run, file, line};
}

static auto output_break() -> void {
  printf(
      "%s[==============================================================]%s\n",
      dim_color, clear_color);
}

static auto output_location(const Instance& test) -> void {
  fputs("    ", stdout);
  Test::print_bytes(test.file, false);
  printf(":%" PRIu64 ": ", test.line);
  Test::print_bytes(test.harness->name, false);
  fputs("::", stdout);
  Test::print_bytes(test.name, false);
}

auto Test::print_integer(int64_t value) -> void {
  printf("%" PRId64, value);
}

auto Test::print_integer(uint64_t value) -> void {
  printf("%" PRIu64, value);
}

auto Test::print_character(unsigned byte, bool different) -> void {
  if (different) {
    fputs(fail_color, stdout);
  }
  fputc(byte, stdout);
  if (different) {
    fputs(clear_color, stdout);
  }
}

int main(int argc, const char* argv[]) {
  const bool silent =
      argc == 2 && !strncmp(argv[1], "silent", sizeof("silent"));
  if (argc > 2 || (argc == 2 && !silent)) {
    fputs("Usage: unit_tests [silent]\n", stderr);
    return 1;
  }

  // Test stat counters for keeping track of all runs.
  uint64_t passed = 0;
  uint64_t failed = 0;
  uint64_t skipped = 0;

  // Loop over all of the tests to figure out how much padding we should add for
  // the name column so all of the timings are aligned. Names should be short so
  // we reserve at least 12 characters of space by default so the read out isn't
  // too cramp.
  uint64_t width = 12;
  for (uint64_t i = 0; i < count; ++i) {
    const auto length = tests[i].name.size;
    if (length > width) {
      width = length;
    }
  }

  const Harness* active = nullptr;
  const uint64_t started = time_ns();
  if (!silent) {
    output_break();
    printf(
        "%s  Tests found: %" PRIu64 "%s\n", heading_color, count, clear_color);
    output_break();
  }

  for (uint64_t i = 0; i < count; ++i) {
    auto& test = tests[i];

    // Tests are logged in registration order. If the test harness changed then
    // we can assume the user is starting a new harness so we'll need to call
    // `init` on the current harness.
    //
    // If the user reuses the harness after a transition then we will open it up
    // as a second instance and call `init` again.
    if (active != test.harness) {
      active = test.harness;
      if (!silent) {
        printf("%s[ START ] ", dim_color);
        Test::print_bytes(active->name, false);
        printf("%s\n", clear_color);
      }

      if (active->init) {
        active->init();
      }
    }

    // Harness setup is excluded from test time.
    if (active->setup) {
      active->setup();
    }

    const uint64_t begin = time_ns();

    // The test framework uses macros that assume result is TestResult::Pass by
    // default and use setting the value directly to side step injecting a bunch
    // of control flow in the test code. We create a reference here on the stack
    // to hold the value directly.
    Test::TestResult result = Test::TestResult::Pass;
    test.run(result);

    const double milliseconds = (time_ns() - begin) / 1'000'000.0;

    // The registration already carries the test's name and source location.
    // Keep its outcome and timing there too so the final report can point to
    // every failure and slow test after the individual output has scrolled by.
    test.result = result;
    test.milliseconds = milliseconds;

    // Regardless of the test result we always perform teardown.
    if (active->teardown) {
      active->teardown();
    }

    // Determine the outcome of the test and record the appropriate stats along
    // with the the result text and color.
    const char* outcome;
    const char* color;
    switch (result) {
    case Test::TestResult::Pass:
      ++passed;
      outcome = "PASS";
      color = pass_color;
      break;
    case Test::TestResult::Failed:
      ++failed;
      outcome = "FAIL";
      color = fail_color;
      break;
    case Test::TestResult::Skipped:
      ++skipped;
      outcome = "SKIP";
      color = skip_color;
      break;
    default:
      ++failed;
      outcome = "INVALID";
      color = fail_color;
      break;
    }

    if (!silent || result != Test::TestResult::Pass) {
      printf("%s  [ %-7s ] ", color, outcome);
      Test::print_bytes(test.name, false);
      for (auto padding = test.name.size; padding < width + 2; ++padding) {
        putchar(' ');
      }
      printf("%s  (%g ms)%s\n", dim_color, milliseconds, clear_color);
    }
  }

  // Skipped tests have no pass or fail result. Excluding them keeps the rate
  // about the tests that completed, while the skip count stays visible above.
  // An empty run or a run with only skips has no rate to report.
  const uint64_t completed = passed + failed;

  // Overall time includes the harness work and individual test output. Stop
  // that measurement before formatting the final report.
  const double total_ms = (time_ns() - started) / 1'000'000.0;
  if (!silent) {
    output_break();

    printf("%s\n  Testing Completed:%s\n", heading_color, clear_color);
    printf("%s      Passed:  %" PRIu64 "%s\n", pass_color, passed, clear_color);
    printf(
        "%s      Failed:  %" PRIu64 "%s\n", failed ? fail_color : dim_color,
        failed, clear_color);
    printf(
        "%s     Skipped:  %" PRIu64 "%s\n", skipped ? skip_color : dim_color,
        skipped, clear_color);
    printf(
        "\n%s  Pass Rate:%s   %" PRIu64 " / %" PRIu64, heading_color,
        clear_color, passed, completed);
    if (completed) {
      printf(" (%.2f%%)\n", 100.0 * passed / completed);
    } else {
      printf(" (n/a)\n");
    }

    printf(
        "%s  Total Time:%s  %g ms\n\n", heading_color, clear_color, total_ms);
    output_break();
  }

  // These lists remain useful in silent runs. Keep each file:line: together
  // so terminals and editors can recognize it as a source link.
  if (failed) {
    printf("%s\n  Failed tests:%s\n", fail_color, clear_color);
    for (uint64_t i = 0; i < count; ++i) {
      const auto& test = tests[i];
      if (test.result != Test::TestResult::Pass &&
          test.result != Test::TestResult::Skipped) {
        output_location(test);
        putchar('\n');
      }
    }
  }

  // Report each test over the threshold, including a passing test hidden by
  // silent mode. Setup and teardown are outside these recorded durations.
  bool slow_heading = false;
  for (uint64_t i = 0; i < count; ++i) {
    const auto& test = tests[i];
    if (test.milliseconds >= slow_test_ms) {
      if (!slow_heading) {
        printf(
            "%s\n  Slow tests (>= %g ms):%s\n", skip_color, slow_test_ms,
            clear_color);
        slow_heading = true;
      }

      output_location(test);
      printf(" (%g ms)\n", test.milliseconds);
    }
  }

  return failed ? 1 : 0;
}
