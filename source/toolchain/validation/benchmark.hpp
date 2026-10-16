// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/validation/harness.hpp"

namespace Toolchain::Validation {

class Benchmark {
 public:
  using BenchmarkFunc = void (*)();
  using Counter = U64 (*)();

  // Construction registers a body for repeated measurement. Its harness, name
  // and callback remain borrowed for the lifetime of the runner, as with tests.
  Benchmark(const Harness& harness, Bytes<> name, BenchmarkFunc run);

  // The runner times the whole body by default. `start_time` begins or restarts
  // a focused interval, and `end_time` records the end paired with the latest
  // start. An open interval receives the body return time as its end. Timing
  // calls govern the current invocation and run on the same thread as the body.
  // The benchmark owns consistency across invocations by selecting the same
  // logical region whenever its samples need to remain comparable.
  static auto start_time() -> void;
  static auto end_time() -> void;

  // Register one cumulative counter before `main` begins. The report shows its
  // change per invocation.
  // The name and callback remain borrowed. Once a counter is registered,
  // another registration returns false and preserves it. Reads begin after
  // fixture setup and end before teardown, bracketing the whole body. A focused
  // timed interval keeps that counter interval intact, so time and event totals
  // can cover different amounts of work. The callback supplies the event
  // meaning.
  static auto register_counter(Bytes<> name, Counter read) -> bool;

  // Keep the result as an input and output of an opaque assembly statement so
  // the compiler retains the work producing it. The memory clobber also marks
  // memory as potentially changed at this point.
  template <typename T>
  static auto prevent_optimization(T& value) -> void {
    asm volatile("" : "+r,m"(value) : : "memory");
  }
};

}  // namespace Toolchain::Validation

#define VALIDATION_BENCHMARK(harness, name)                         \
  static auto validation_benchmark_##harness##_##name() -> void;    \
  static Toolchain::Validation::Benchmark                           \
      validation_benchmark_entry_##harness##_##name(                \
          harness, #name, validation_benchmark_##harness##_##name); \
  static auto validation_benchmark_##harness##_##name() -> void
