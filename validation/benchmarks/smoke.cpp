// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include <stdio.h>

#include "toolchain/validation/benchmark.hpp"

using namespace Toolchain::Validation;

// These counts are observed after the real benchmark process returns from
// main. Warm up and measured bodies share the same fixture lifecycle.
struct Fixture {
  U32 initializations = 0;
  U32 setups = 0;
  U32 runs = 0;
  U32 teardowns = 0;
  U32 errors = 0;
  U64 events = 0;
  bool ready = false;
  U32 values[64] = {};

  Fixture() { puts("benchmark fixture constructed"); }
  ~Fixture() {
    printf(
        "benchmark fixture destroyed: init=%u setup=%u run=%u teardown=%u "
        "errors=%u ready=%d\n",
        initializations, setups, runs, teardowns, errors, ready);
  }
};

static Fixture fixture;
static const bool registered =
    Benchmark::register_counter("Events", [] { return fixture.events; });
static Harness Arithmetic = {
  .name = "Arithmetic",
  .init = [] { ++fixture.initializations; },
  .setup =
      [] {
        if (fixture.ready) {
          ++fixture.errors;
        }

        for (U32 i = 0; i < 64; ++i) {
          fixture.values[i] = i;
        }

        fixture.ready = true;
        ++fixture.setups;
      },
  .teardown =
      [] {
        if (!fixture.ready) {
          ++fixture.errors;
        }

        fixture.ready = false;
        ++fixture.teardowns;
      },
};

static auto sum() -> U32 {
  if (!fixture.ready || !registered || fixture.initializations != 1) {
    ++fixture.errors;
  }

  U32 total = 0;
  for (const auto value : fixture.values) {
    total += value;
  }

  ++fixture.runs;
  fixture.events += 2;
  return total;
}

VALIDATION_BENCHMARK(Arithmetic, sum) {
  auto total = sum();
  Benchmark::prevent_optimization(total);
}

VALIDATION_BENCHMARK(Arithmetic, timed_sum) {
  Benchmark::start_time();

  auto total = sum();
  Benchmark::prevent_optimization(total);
  Benchmark::end_time();
}
