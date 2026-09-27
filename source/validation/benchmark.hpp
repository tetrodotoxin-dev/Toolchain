// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/validation/harness.hpp"

namespace Toolchain::Validation::Benchmark {

using BenchmarkFunc = void (*)();
using Counter = unsigned long long (*)();

auto create(const Harness& harness, const char* name, BenchmarkFunc run)
    -> void;
auto start_time() -> void;
auto end_time() -> void;
auto run(int argc, const char* const* argv) -> int;

// A project may report one cumulative counter alongside elapsed time. The
// runner samples it outside the timed interval and knows nothing about the
// allocator or service being observed. Its name and callback remain borrowed.
auto register_counter(const char* name, Counter read) -> bool;

template <typename T>
inline auto prevent_optimization(T& value) -> void {
  asm volatile("" : "+r,m"(value) : : "memory");
}

class BenchmarkEntry {
 public:
  BenchmarkEntry(const Harness& harness, const char* name, BenchmarkFunc run) {
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
