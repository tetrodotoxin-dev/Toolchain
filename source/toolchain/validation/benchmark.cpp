// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/benchmark.hpp"

#include <stdio.h>
#include <stdlib.h>

#include "toolchain/validation/clock.hpp"

using namespace Toolchain::Validation;

static const char* clear_color = getenv("NO_COLOR") ? "" : "\x1b[0m";
static const char* heading_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;124m";
static const char* dim_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;246m";
static const char* fast_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;34m";
static const char* slow_color = getenv("NO_COLOR") ? "" : "\x1b[38;5;160m";
static Clock monotonic_clock;

struct Instance {
  const Harness* harness;
  Bytes<> name;
  Benchmark::BenchmarkFunc run;
};

// Static storage gives registrations stable addresses for the process lifetime.
// The fixed capacities bound startup and measurement work, while constinit
// completes initialization before benchmark constructors begin registering.
static constinit Instance benchmarks[1024] = {};
static CppSize count = 0;
static U64 samples[4096];
static U64 sample_start = 0;
static U64 sample_end = 0;

Benchmark::Benchmark(const Harness& harness, Bytes<> name, BenchmarkFunc run) {
  if (count == sizeof(benchmarks) / sizeof(*benchmarks)) {
    fputs("Benchmark registration capacity exceeded.\n", stderr);
    abort();
  }

  benchmarks[count++] = {&harness, name, run};
}

// One process wide counter gives every reported row the same event unit. The
// first registration establishes that unit for the complete benchmark suite.
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
  // A new start begins a focused interval and clears its end marker, pairing
  // both timestamps with the current invocation.
  sample_start = monotonic_clock.time_ns();
  sample_end = 0;
}

auto Benchmark::end_time() -> void {
  sample_end = monotonic_clock.time_ns();
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

  for (CppSize i = 0; i < prefix.size; ++i) {
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

static auto output_name(Bytes<> name, CppSize width = 0) -> void {
  if (name.size) {
    fwrite(name.data, 1, name.size, stdout);
  }

  for (CppSize i = name.size; i < width; ++i) {
    putchar(' ');
  }
}

static auto average(CppSize begin, CppSize end) -> R64 {
  // Average in nanoseconds before converting to microseconds so a short
  // operation keeps its fractional time in the report.
  R64 total = 0;
  for (CppSize i = begin; i < end; ++i) {
    total += samples[i];
  }

  return total / (end - begin) / 1000;
}

static auto sort_samples(CppSize size) -> void {
  // Halving gaps keep report preparation bounded while the final unit gap
  // establishes the exact order used by the percentile groups.
  for (CppSize gap = size / 2; gap; gap /= 2) {
    for (CppSize index = gap; index < size; ++index) {
      const U64 selected = samples[index];
      CppSize cursor = index;
      while (cursor >= gap && samples[cursor - gap] > selected) {
        samples[cursor] = samples[cursor - gap];
        cursor -= gap;
      }

      samples[cursor] = selected;
    }
  }
}

static auto measure(const Instance& benchmark, CppSize width) -> void {
  const auto& harness = *benchmark.harness;

  // One complete fixture invocation warms the code and data. Sample and counter
  // collection begin with the following invocation.
  if (harness.setup) {
    harness.setup();
  }

  benchmark.run();
  if (harness.teardown) {
    harness.teardown();
  }

  CppSize sample_count = 0;
  U64 events = 0;
  const U64 started = monotonic_clock.time_ns();
  while (sample_count < sizeof(samples) / sizeof(*samples)) {
    if (harness.setup) {
      harness.setup();
    }

    // Counter reads bracket the complete body. The timed interval may select a
    // narrower region while the event count continues to describe one complete
    // invocation.
    const auto before = counter ? counter() : 0;
    Benchmark::start_time();
    benchmark.run();

    // A body that leaves its interval open receives its return time as the end.
    if (!sample_end) {
      Benchmark::end_time();
    }

    samples[sample_count++] = sample_end - sample_start;
    if (counter) {
      events += counter() - before;
    }

    // The sample becomes final before fixture teardown. The run budget covers
    // the complete fixture lifecycle, while the report presents the body span.
    if (harness.teardown) {
      harness.teardown();
    }

    // Check elapsed time once per sixteen samples to limit clock overhead for
    // short bodies. This is a soft budget: every invocation finishes, and at
    // least sixteen samples are collected even when a benchmark is slow.
    if (!(sample_count & 15) &&
        monotonic_clock.time_ns() - started >= 1'500'000'000) {
      break;
    }
  }

  // Sort the measurements into fast, middle and slow groups. Round each outer
  // group down to a whole sample and keep the remainder in the middle.
  // With at least sixteen samples, all three groups are nonempty and every
  // sample contributes to exactly one mean.
  sort_samples(sample_count);

  const CppSize tenth = sample_count / 10;
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

S32 main(S32 argc, const char* argv[]) {
  if (argc > 2) {
    fputs("Usage: benchmarks [name-prefix]\n", stderr);
    return 1;
  }

  // An empty prefix selects the complete suite. A supplied prefix selects
  // matching harnesses or individual benchmarks regardless of case, and an
  // unmatched prefix produces an empty measurement report.
  // One byte past the longest registered name distinguishes an oversized
  // filter. argv supplies terminated strings, so short inputs stop at their
  // zero.
  CppSize longest = 0;
  for (CppSize i = 0; i < count; ++i) {
    if (benchmarks[i].name.size > longest) {
      longest = benchmarks[i].name.size;
    }

    if (benchmarks[i].harness->name.size > longest) {
      longest = benchmarks[i].harness->name.size;
    }
  }

  const Bytes<> filter =
      argc == 2 ? convert_cstring(argv[1], longest + 1) : Bytes<>{};
  CppSize width = 26;
  for (CppSize i = 0; i < count; ++i) {
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

  // A registered counter extends every row with its shared event unit.
  if (counter) {
    putchar(' ');
    for (CppSize i = counter_name.size; i < 14; ++i) {
      putchar(' ');
    }

    output_name(counter_name);
  }

  putchar('\n');
  output_break();

  const Harness* active = nullptr;
  for (CppSize i = 0; i < count; ++i) {
    const auto& benchmark = benchmarks[i];
    if (!matches(benchmark.name, filter) &&
        !matches(benchmark.harness->name, filter)) {
      continue;
    }

    // Preserve registration order. As in the test runner, each transition to
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
