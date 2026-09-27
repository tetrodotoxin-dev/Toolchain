// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/clock.hpp"

#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

using namespace Toolchain::Validation;

auto Toolchain::Validation::time_ns() -> uint64_t {
#ifdef _WIN32
  LARGE_INTEGER counter;
  LARGE_INTEGER frequency;
  QueryPerformanceCounter(&counter);
  QueryPerformanceFrequency(&frequency);
  const uint64_t ticks = uint64_t(counter.QuadPart);
  const uint64_t rate = uint64_t(frequency.QuadPart);
  return ticks / rate * 1'000'000'000 + ticks % rate * 1'000'000'000 / rate;
#else
  timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return uint64_t(value.tv_sec) * 1'000'000'000 + uint64_t(value.tv_nsec);
#endif
}
