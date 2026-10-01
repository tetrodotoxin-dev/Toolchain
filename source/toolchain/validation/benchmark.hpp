// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/validation/harness.hpp"

namespace Toolchain::Validation::Benchmark {

using BenchmarkFunc = void (*)();
using Counter = unsigned long long (*)();

// Register a body for repeated measurement. Its harness, name and callback
// remain borrowed for the lifetime of the runner, as with unit tests.
auto create(const Harness& harness, Bytes<> name, BenchmarkFunc run) -> void;

// The runner times the whole body by default. A body can call `start_time`
// after local preparation and `end_time` before cleanup to measure a smaller
// interval. Each start clears the earlier end. If the body leaves the interval
// open, the runner closes it when the body returns. Timing calls govern the
// current invocation and run on the same thread as the body.
auto start_time() -> void;
auto end_time() -> void;

// Register one cumulative counter before `main` begins. The report shows its
// change per invocation.
// The name and callback remain borrowed. Once a counter is registered, another
// registration returns false and preserves it. Reads bracket the whole body,
// excluding fixture setup and teardown. Shortening the timed interval leaves
// this counter interval unchanged, so time and event totals can cover different
// amounts of work. The callback supplies the meaning of the counted events.
auto register_counter(Bytes<> name, Counter read) -> bool;

// Keep the result as an input and output of an opaque assembly statement so
// the compiler retains the work producing it. The memory clobber also marks
// memory as potentially changed at this point.
template <typename T>
inline auto prevent_optimization(T& value) -> void {
  asm volatile("" : "+r,m"(value) : : "memory");
}

class BenchmarkEntry {
 public:
  BenchmarkEntry(const Harness& harness, Bytes<> name, BenchmarkFunc run) {
    create(harness, name, run);
  }
};

}  // namespace Toolchain::Validation::Benchmark

#define VALIDATION_BENCHMARK(harness, name)                      \
  static auto validation_benchmark_##harness##_##name() -> void; \
  namespace {                                                    \
  Toolchain::Validation::Benchmark::BenchmarkEntry               \
      validation_benchmark_entry_##harness##_##name(             \
          harness,                                               \
          #name,                                                 \
          validation_benchmark_##harness##_##name);              \
  }                                                              \
  static auto validation_benchmark_##harness##_##name() -> void
