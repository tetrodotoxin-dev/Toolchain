// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/test.hpp"

#include <stdlib.h>

#include "toolchain/validation/clock.hpp"

using namespace Toolchain::Validation;

static const char* clear_color = getenv("NO_COLOR") ? "" : "\x1b[0m";
static const char* heading_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;124m";
static const char* dim_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;246m";
static const char* pass_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;34m";
static const char* fail_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;160m";
static const char* skip_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;178m";
static Clock monotonic_clock;

struct Instance {
  const Harness* harness;
  Bytes<> name;
  Test::TestFunc run;
  Bytes<> file;
  U64 line;
  Test::TestResult result = Test::TestResult::Pass;
  R64 milliseconds = 0;
};

// The slow threshold shares the report's millisecond unit and supplements each
// test's pass, fail or skip result.
static constexpr R64 slow_test_ms = 1000;

// Static storage gives registrations stable addresses for the process lifetime.
// The fixed capacity bounds startup work, and constinit keeps initialization
// complete before constructors in test translation units begin registering.
static constinit Instance tests[4096] = {};
static U64 count = 0;

// Registration order defines execution order. Reaching the fixed capacity is a
// suite configuration error, so registration reports it and terminates startup.
Test::Test(
    const Harness& harness,
    Bytes<> name,
    TestFunc run,
    Bytes<> file,
    U64 line) {
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
  printf(":%llu: ", test.line);
  Test::print_bytes(test.harness->name, false);
  fputs("::", stdout);
  Test::print_bytes(test.name, false);
}

auto Test::print_integer(S64 value) -> void {
  printf("%lld", value);
}

auto Test::print_integer(U64 value) -> void {
  printf("%llu", value);
}

auto Test::print_character(U32 byte, bool different) -> void {
  if (different) {
    fputs(fail_color, stdout);
  }

  fputc(byte, stdout);
  if (different) {
    fputs(clear_color, stdout);
  }
}

S32 main(S32 argc, const char* argv[]) {
  const bool silent =
      argc == 2 && !strncmp(argv[1], "silent", sizeof("silent"));
  if (argc > 2 || (argc == 2 && !silent)) {
    fputs("Usage: tests [silent]\n", stderr);
    return 1;
  }

  U64 passed = 0;
  U64 failed = 0;
  U64 skipped = 0;

  // Twelve columns keep short names readable. Longer registrations expand the
  // column so every duration remains aligned.
  U64 width = 12;
  for (U64 i = 0; i < count; ++i) {
    const auto length = tests[i].name.size;
    if (length > width) {
      width = length;
    }
  }

  const Harness* active = nullptr;
  const U64 started = monotonic_clock.time_ns();
  if (!silent) {
    output_break();
    printf("%s  Tests found: %llu%s\n", heading_color, count, clear_color);
    output_break();
  }

  for (U64 i = 0; i < count; ++i) {
    auto& test = tests[i];

    // Each contiguous run of one harness forms an initialized group. Returning
    // to an earlier harness starts another group and invokes its initializer
    // again, preserving registration order as the complete scheduling rule.
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

    // Body timing begins after harness setup completes.
    if (active->setup) {
      active->setup();
    }

    const U64 begin = monotonic_clock.time_ns();

    // Assertion macros write one stack result initialized to Pass. This keeps
    // result control flow in the runner while ASSERT may still return from the
    // registered body immediately.
    Test::TestResult result = Test::TestResult::Pass;
    test.run(result);

    const R64 milliseconds = (monotonic_clock.time_ns() - begin) / 1'000'000.0;

    // The registration already carries the test's name and source location.
    // Keep its outcome and timing there too so the final report can point to
    // every failure and slow test after the individual output has scrolled by.
    test.result = result;
    test.milliseconds = milliseconds;

    // Every completed body is paired with its harness teardown.
    if (active->teardown) {
      active->teardown();
    }

    // One result selects the aggregate count, report label and display color.
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
      outcome = "????";
      color = fail_color;
      break;
    }

    if (!silent || result != Test::TestResult::Pass) {
      printf("%s  [ %-4s ] ", color, outcome);
      Test::print_bytes(test.name, false);
      for (auto padding = test.name.size; padding < width + 2; ++padding) {
        putchar(' ');
      }

      printf("%s  (%g ms)%s\n", dim_color, milliseconds, clear_color);
    }
  }

  // The pass rate describes completed tests, while skips retain their separate
  // count. A run with zero completed tests reports an inapplicable rate.
  const U64 completed = passed + failed;

  // Overall time includes the harness work and individual test output. Stop
  // that measurement before formatting the final report.
  const R64 total_ms = (monotonic_clock.time_ns() - started) / 1'000'000.0;
  if (!silent) {
    output_break();

    printf("%s\n  Testing Completed:%s\n", heading_color, clear_color);
    printf("%s      Passed:  %llu%s\n", pass_color, passed, clear_color);
    printf(
        "%s      Failed:  %llu%s\n", failed ? fail_color : dim_color, failed,
        clear_color);
    printf(
        "%s     Skipped:  %llu%s\n", skipped ? skip_color : dim_color, skipped,
        clear_color);
    printf(
        "\n%s  Pass Rate:%s   %llu / %llu", heading_color, clear_color, passed,
        completed);
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
    for (U64 i = 0; i < count; ++i) {
      const auto& test = tests[i];
      if (test.result != Test::TestResult::Pass &&
          test.result != Test::TestResult::Skipped) {
        output_location(test);
        putchar('\n');
      }
    }
  }

  // The slow list includes every body over the threshold, including passing
  // tests hidden by silent mode. Recorded durations cover the body itself.
  bool slow_heading = false;
  for (U64 i = 0; i < count; ++i) {
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
