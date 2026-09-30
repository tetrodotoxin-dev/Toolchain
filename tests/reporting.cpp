// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include <inttypes.h>
#include <stdlib.h>

#include "toolchain/validation/unit_test.hpp"

#ifdef _WIN32
#include <io.h>
#define dup _dup
#define dup2 _dup2
#define fileno _fileno
#define close _close
#else
#include <unistd.h>
#endif

#include "toolchain/validation/clock.hpp"
#include "toolchain/validation/stream.hpp"

using namespace Toolchain::Validation;

static uint64_t now = 0;
static char output[8192];
static Test::TestResult results[] = {
  Test::TestResult::Pass, Test::TestResult::Failed, Test::TestResult::Failed,
  Test::TestResult::Skipped};
static uint64_t durations[] = {1'000'000'000, 999'999'999, 1'500'000'000, 0};
static unsigned teardowns = 0;

// The runner uses its ordinary clock symbol. Supplying deterministic time in
// this binary tests the warning boundary without waiting or depending on load.
auto Toolchain::Validation::time_ns() -> uint64_t {
  return now;
}

static auto require(bool condition, const char* message) -> void {
  if (!condition) {
    fprintf(stderr, "%s\n", message);
    exit(1);
  }
}

// Capture the real FILE output in this process, then restore stdout before
// checking it so a failed expectation remains visible to the test runner.
static auto capture(bool silent = false) -> int {
  FILE* transcript = temporary_stream();
  require(transcript != nullptr, "Could not open the report transcript");
  require(fflush(stdout) == 0, "Could not flush stdout before capture");
  const int saved = dup(fileno(stdout));
  require(saved >= 0, "Could not retain stdout");
  require(
      dup2(fileno(transcript), fileno(stdout)) >= 0,
      "Could not capture stdout");

  const char* arguments[] = {"reporting", "silent"};
  const int status = Test::run(silent ? 2 : 1, arguments);

  require(fflush(stdout) == 0, "Could not flush the report");
  require(dup2(saved, fileno(stdout)) >= 0, "Could not restore stdout");
  close(saved);
  rewind(transcript);
  const auto size = fread(output, 1, sizeof(output) - 1, transcript);
  require(
      !ferror(transcript) && size < sizeof(output) - 1,
      "Report capture was incomplete");
  output[size] = 0;
  fclose(transcript);
  return status;
}

static auto run_case(unsigned index, Test::TestResult& result) -> void {
  result = results[index];
  now += durations[index];
}

static auto expect_location(const char* report, uint64_t line, const char* name)
    -> const char* {
  char location[1024];
  snprintf(
      location, sizeof(location), "%s:%" PRIu64 ": Reporting::%s", __FILE__,
      line, name);
  const auto* found = strstr(report, location);
  require(found != nullptr, "Report omitted a test's source location");
  return found;
}

int main() {
  require(capture() == 0, "An empty run failed");
  require(strstr(output, "0 / 0 (n/a)"), "An empty run reported a percentage");

  // Setup and teardown each take longer than the warning threshold. Only a
  // test body's duration should decide which tests enter the slow list.
  static Harness harness = {
    .name = "Reporting",
    .setup = [] { now += 2'000'000'000; },
    .teardown =
        [] {
          now += 2'000'000'000;
          ++teardowns;
        },
  };

  const uint64_t pass_line = __LINE__;
  Test::create(
      harness, "slow_pass", [](auto& result) { run_case(0, result); }, __FILE__,
      pass_line);
  const uint64_t fail_line = __LINE__;
  Test::create(
      harness, "failure", [](auto& result) { run_case(1, result); }, __FILE__,
      fail_line);
  const uint64_t slow_fail_line = __LINE__;
  Test::create(
      harness, "slow_failure", [](auto& result) { run_case(2, result); },
      __FILE__, slow_fail_line);
  Test::create(
      harness, "skipped", [](auto& result) { run_case(3, result); }, __FILE__,
      __LINE__);

  require(capture() == 1, "A run containing failures succeeded");
  require(
      strstr(output, "1 / 3 (33.33%)"), "Pass rate included the skipped test");
  const auto* failures = strstr(output, "Failed tests:");
  const auto* slow = strstr(output, "Slow tests (>= 1000 ms):");
  require(failures && slow, "The final report omitted a result list");
  require(
      expect_location(failures, fail_line, "failure") < slow,
      "The first failure was absent from the failure list");
  require(
      expect_location(failures, slow_fail_line, "slow_failure") < slow,
      "The second failure was absent from the failure list");
  expect_location(slow, pass_line, "slow_pass");
  expect_location(slow, slow_fail_line, "slow_failure");
  require(
      !strstr(slow, "Reporting::failure"),
      "Fixture time entered the slow test duration");
  require(teardowns == 4, "A failure or skip bypassed teardown");

  require(capture(true) == 1, "Silent mode hid the failure status");
  failures = strstr(output, "Failed tests:");
  slow = strstr(output, "Slow tests (>= 1000 ms):");
  require(failures && slow, "Silent mode hid actionable results");
  expect_location(failures, fail_line, "failure");
  expect_location(failures, slow_fail_line, "slow_failure");
  expect_location(slow, pass_line, "slow_pass");
  require(
      !strstr(output, "Pass Rate:"), "Silent mode printed the regular summary");

  for (unsigned i = 0; i < 4; ++i) {
    results[i] = Test::TestResult::Skipped;
    durations[i] = 0;
  }
  require(capture() == 0, "A run containing only skips failed");
  require(
      strstr(output, "0 / 0 (n/a)"),
      "A run containing only skips reported a percentage");
  require(
      !strstr(output, "Failed tests:") && !strstr(output, "Slow tests"),
      "A repeated run retained earlier results");

  for (auto& result : results) {
    result = Test::TestResult::Pass;
  }
  require(capture() == 0, "A passing run failed");
  require(
      strstr(output, "4 / 4 (100.00%)"), "The complete pass rate was missing");
  require(
      capture(true) == 0 && !*output, "A passing silent run printed output");
  puts("Runner reporting checks passed.");
}
