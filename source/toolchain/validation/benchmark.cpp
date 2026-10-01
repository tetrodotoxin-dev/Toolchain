// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/benchmark.hpp"

#include <algorithm>
#include <stdio.h>
#include <stdlib.h>

#include "toolchain/validation/clock.hpp"

using namespace Toolchain::Validation;

static const char* clear_color = getenv("NO_COLOR") ? "" : "\x1b[0m";
static const char* heading_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;124m";
static const char* dim_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;246m";
static const char* fast_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;34m";
static const char* slow_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;160m";

struct Instance {
  const Harness* harness;
  Bytes<> name;
  Benchmark::BenchmarkFunc run;
};

// Static registration allows for easily adding tests without requiring global
// static clean up. 1k cases should be more than enough for any realistic test
// suite but the number can always be expanded if required.
// Every field is initialized before registration in other translation units.
// constinit catches a member that would reset those registrations at startup.
static constinit Instance benchmarks[1024] = {};
static size_t count = 0;
static uint64_t samples[4096];
static uint64_t sample_start = 0;
static uint64_t sample_end = 0;
auto Benchmark::create(const Harness& harness, Bytes<> name, BenchmarkFunc run)
    -> void {
  if (count == sizeof(benchmarks) / sizeof(*benchmarks)) {
    fputs("Benchmark registration capacity exceeded.\n", stderr);
    abort();
  }

  benchmarks[count++] = {&harness, name, run};
}

// Give benchmarks static storage for registering a single named counter. In the
// future if we decide to expand this we can allow for multiple, but allowing a
// bunch of high performance counters generically is outside of the scope of
// this simple benchmark library.
//
// The counter is currently set for the entire benchmark suite.
static constinit Bytes<> counter_name;
static Benchmark::Counter counter = nullptr;

auto Benchmark::register_counter(Bytes<> name, Counter read) -> bool {
  if (counter) {
    return false;
  }

  counter_name = name;
  counter = read;
  return true;
}

auto Benchmark::start_time() -> void {
  // A benchmark may move its starting point past some local preparation in
  // order to get a more focused measurement. Clear the old end as well so it
  // cannot be paired with the replacement interval.
  sample_start = time_ns();
  sample_end = 0;
}

auto Benchmark::end_time() -> void {
  sample_end = time_ns();
}

static auto output_break() -> void {
  printf(
      "%s[==============================================================]%s\n",
      dim_color, clear_color);
}

static auto matches(Bytes<> name, Bytes<> prefix) -> bool {
  if (prefix.size > name.size) {
    return false;
  }
  for (size_t i = 0; i < prefix.size; ++i) {
    auto left = name.data[i];
    auto right = prefix.data[i];
    if (left >= 'A' && left <= 'Z') {
      left += 'a' - 'A';
    }
    if (right >= 'A' && right <= 'Z') {
      right += 'a' - 'A';
    }
    if (left != right) {
      return false;
    }
  }

  return true;
}

static auto output_name(Bytes<> name, size_t width = 0) -> void {
  if (name.size) {
    fwrite(name.data, 1, name.size, stdout);
  }
  for (size_t i = name.size; i < width; ++i) {
    putchar(' ');
  }
}

static auto average(size_t begin, size_t end) -> double {
  // Average in nanoseconds before converting to microseconds so a short
  // operation keeps its fractional time in the report.
  double total = 0;
  for (size_t i = begin; i < end; ++i) {
    total += samples[i];
  }

  return total / (end - begin) / 1000;
}

static auto measure(const Instance& benchmark, size_t width) -> void {
  const auto& harness = *benchmark.harness;

  // Run once with the same setup and teardown as a measured invocation. This
  // warms the code and its data before collecting the cost of repeated work.
  // Both the warm up time and its counter changes stay outside the samples.
  if (harness.setup) {
    harness.setup();
  }

  benchmark.run();
  if (harness.teardown) {
    harness.teardown();
  }

  size_t sample_count = 0;
  unsigned long long events = 0;
  const uint64_t started = time_ns();
  while (sample_count < sizeof(samples) / sizeof(*samples)) {
    if (harness.setup) {
      harness.setup();
    }

    // Counter reads surround the whole body and stay outside its timed
    // interval. A body can narrow that interval with `start_time` and
    // `end_time`, while the counter still describes the full invocation.
    const auto before = counter ? counter() : 0;
    Benchmark::start_time();
    benchmark.run();

    // If no end was provided use now as the end time.
    if (!sample_end) {
      Benchmark::end_time();
    }

    samples[sample_count++] = sample_end - sample_start;
    if (counter) {
      events += counter() - before;
    }

    // Finish collecting the sample before tearing down its fixture. The run
    // budget below includes fixture work, but the reported body time does not.
    if (harness.teardown) {
      harness.teardown();
    }

    // Check elapsed time once per sixteen samples to limit clock overhead for
    // short bodies. This is a soft budget: every invocation finishes, and at
    // least sixteen samples are collected even when a benchmark is slow.
    if (!(sample_count & 15) && time_ns() - started >= 1'500'000'000) {
      break;
    }
  }

  // Sort the measurements into fast, middle and slow groups. Round each outer
  // group down to a whole sample and keep the remainder in the middle.
  // With at least sixteen samples, all three groups are nonempty and every
  // sample contributes to exactly one mean.
  std::sort(samples, samples + sample_count);
  const size_t tenth = sample_count / 10;
  fputs("  ", stdout);
  output_name(benchmark.name, width);
  printf(
      " %s%10.3f%s %10.3f %s%10.3f%s", fast_color, average(0, tenth),
      clear_color, average(tenth, sample_count - tenth), slow_color,
      average(sample_count - tenth, sample_count), clear_color);

  if (counter) {
    printf(" %14.2f", 1.0 * events / sample_count);
  }

  putchar('\n');
}

int main(int argc, const char* argv[]) {
  if (argc > 2) {
    fputs("Usage: benchmarks [name-prefix]\n", stderr);
    return 1;
  }

  // Unit tests don't provide filtering to avoid bad habits around ignoring
  // tests, but unlike unit tests a total benchmark suite can take several
  // minutes to run.
  //
  // A prefix name can be used to select either a harness or an individual
  // benchmark. Only the selected names are measured with a bad selection
  // running nothing.
  // One byte past the longest registered name is enough to reject an oversized
  // filter. argv supplies terminated strings, so short inputs stop at their
  // zero.
  size_t longest = 0;
  for (size_t i = 0; i < count; ++i) {
    longest = std::max(
        longest,
        std::max(benchmarks[i].name.size, benchmarks[i].harness->name.size));
  }
  const Bytes<> filter =
      argc == 2 ? convert_cstring(argv[1], longest + 1) : Bytes<>{};
  size_t width = 26;
  for (size_t i = 0; i < count; ++i) {
    const auto& benchmark = benchmarks[i];
    if (matches(benchmark.name, filter) ||
        matches(benchmark.harness->name, filter)) {
      const auto length = benchmark.name.size;
      if (length > width) {
        width = length;
      }
    }
  }

  output_break();
  printf(
      "%s  Benchmark times in microseconds.%s\n", heading_color, clear_color);
  fputs("  ", stdout);
  output_name("Name", width);
  printf(" %10s %10s %10s", "Fast 10%", "Middle 80%", "Slow 10%");

  // Log a counter if one was provided.
  if (counter) {
    putchar(' ');
    for (size_t i = counter_name.size; i < 14; ++i) {
      putchar(' ');
    }
    output_name(counter_name);
  }

  putchar('\n');
  output_break();

  const Harness* active = nullptr;
  for (size_t i = 0; i < count; ++i) {
    const auto& benchmark = benchmarks[i];
    if (!matches(benchmark.name, filter) &&
        !matches(benchmark.harness->name, filter)) {
      continue;
    }

    // Preserve registration order. As in the unit runner, each transition to
    // a different harness starts a new group and calls its `init` hook. Setup
    // and teardown belong to the individual invocations inside `measure`.
    if (active != benchmark.harness) {
      active = benchmark.harness;
      printf("%s[ START ] ", dim_color);
      output_name(active->name);
      printf("%s\n", clear_color);
      if (active->init) {
        active->init();
      }
    }

    measure(benchmark, width);
  }

  output_break();
  return 0;
}
