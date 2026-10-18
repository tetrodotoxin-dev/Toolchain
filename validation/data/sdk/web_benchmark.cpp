// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/benchmark.hpp"

using namespace Toolchain::Validation;

static Harness WebBenchmark = {
  .name = "Web benchmark",
};

VALIDATION_BENCHMARK(WebBenchmark, compiles) {
  Benchmark::prevent_optimization(U32(42));
}
