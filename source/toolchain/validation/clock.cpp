// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/clock.hpp"

#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

using namespace Toolchain::Validation;

auto Clock::time_ns() const -> U64 {

#ifdef _WIN32

  LARGE_INTEGER counter;
  LARGE_INTEGER frequency;
  QueryPerformanceCounter(&counter);
  QueryPerformanceFrequency(&frequency);

  const U64 ticks = counter.QuadPart;
  const U64 rate = frequency.QuadPart;
  return ticks / rate * 1'000'000'000 + ticks % rate * 1'000'000'000 / rate;

#else

  timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);

  const U64 seconds = value.tv_sec;
  const U64 nanoseconds = value.tv_nsec;
  return seconds * 1'000'000'000 + nanoseconds;

#endif
}
