// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/benchmark.hpp"

#include <stdio.h>
#include <stdlib.h>

#include "toolchain/validation/clock.hpp"

using namespace Toolchain::Validation;

struct Instance {
  const Harness* harness;
  const char* name;
  Benchmark::BenchmarkFunc run;
};

static Instance benchmarks[1024];
static size_t count = 0;
static uint64_t samples[4096];
static uint64_t sample_start = 0;
static uint64_t sample_end = 0;
static const char* counter_name = nullptr;
static Benchmark::Counter counter = nullptr;

auto Benchmark::create(
    const Harness& harness,
    const char* name,
    BenchmarkFunc run) -> void {
  if (count == sizeof(benchmarks) / sizeof(*benchmarks)) {
    fputs("Benchmark registration capacity exceeded.\n", stderr);
    abort();
  }
  benchmarks[count++] = {&harness, name, run};
}

auto Benchmark::register_counter(const char* name, Counter read) -> bool {
  if (counter) {
    return false;
  }
  counter_name = name;
  counter = read;
  return true;
}

auto Benchmark::start_time() -> void {
  sample_start = time_ns();
  sample_end = 0;
}

auto Benchmark::end_time() -> void {
  sample_end = time_ns();
}

static auto matches(const char* name, const char* prefix) -> bool {
  while (*prefix) {
    if (!*name || ((*name++ | 0x20) != (*prefix++ | 0x20))) {
      return false;
    }
  }
  return true;
}

static auto compare_samples(const void* left, const void* right) -> int {
  const auto a = *static_cast<const uint64_t*>(left);
  const auto b = *static_cast<const uint64_t*>(right);
  return a < b ? -1 : a > b ? 1 : 0;
}

static auto average(size_t begin, size_t end) -> double {
  double total = 0;
  for (size_t i = begin; i < end; ++i) {
    total += double(samples[i]);
  }
  return total / double(end - begin) / 1000;
}

// Setup and cleanup stay outside the sample. Bodies can narrow their interval
// through start_time and end_time when a fixture cannot own that boundary.
static auto measure(const Instance& benchmark) -> void {
  const auto& harness = *benchmark.harness;
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
    const auto before = counter ? counter() : 0;
    Benchmark::start_time();
    benchmark.run();
    if (!sample_end) {
      Benchmark::end_time();
    }
    samples[sample_count++] = sample_end - sample_start;
    if (counter) {
      events += counter() - before;
    }
    if (harness.teardown) {
      harness.teardown();
    }
    if (!(sample_count & 15) && time_ns() - started >= 1'500'000'000) {
      break;
    }
  }
  qsort(samples, sample_count, sizeof(*samples), compare_samples);
  const size_t tenth = sample_count / 10;
  printf(
      "  %-26s %10.3f %10.3f %10.3f", benchmark.name, average(0, tenth),
      average(tenth, sample_count - tenth),
      average(sample_count - tenth, sample_count));
  if (counter) {
    printf(" %14.2f", double(events) / sample_count);
  }
  putchar('\n');
}

auto Benchmark::run(int argc, const char* const* argv) -> int {
  if (argc > 2) {
    fprintf(stderr, "Usage: %s [name-prefix]\n", argv[0]);
    return 1;
  }
  const char* filter = argc == 2 ? argv[1] : "";
  puts("Benchmark times in microseconds.");
  printf(
      "  %-26s %10s %10s %10s", "Name", "Fast 10%", "Middle 80%", "Slow 10%");
  if (counter) {
    printf(" %14s", counter_name);
  }
  putchar('\n');
  const Harness* active = nullptr;
  for (size_t i = 0; i < count; ++i) {
    const auto& benchmark = benchmarks[i];
    if (!matches(benchmark.name, filter) &&
        !matches(benchmark.harness->name, filter)) {
      continue;
    }
    if (active != benchmark.harness) {
      active = benchmark.harness;
      printf("%s\n", active->name);
      if (active->init) {
        active->init();
      }
    }
    measure(benchmark);
  }
  return 0;
}
