// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once
#include <stdint.h>

#include "toolchain/validation/harness.hpp"

namespace Toolchain::Validation::Process {

// One finite invocation borrows its complete input for run(). Observation
// owns the three captured byte buffers, independently of the tested library.
struct Request {
  Bytes executable;
  const Bytes* arguments = nullptr;
  size_t argument_count = 0;
  Bytes standard_input = {};
  uint64_t timeout_nanoseconds = 1'000'000'000;
};

struct Observation {
  bool launched = false;
  bool timed_out = false;
  int32_t exit_status = -1;
  Bytes standard_input = {};
  Bytes standard_output = {};
  Bytes standard_error = {};
  const char* runner_error = nullptr;

  Observation() = default;
  Observation(const Observation&) = delete;
  auto operator=(const Observation&) -> Observation& = delete;
  Observation(Observation&& other) noexcept;
  ~Observation();
};

struct Expectation {
  bool timed_out = false;
  int32_t exit_status = 0;
  Bytes standard_input = {};
  Bytes standard_output = {};
  Bytes standard_error = {};
};
enum class Difference {
  None,
  Launch,
  StandardInput,
  Timeout,
  StandardOutput,
  StandardError,
  ExitStatus
};
auto run(const Request& request) -> Observation;
auto compare(const Observation& observation, const Expectation& expectation)
    -> Difference;
}  // namespace Toolchain::Validation::Process
