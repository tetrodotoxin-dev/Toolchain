// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/process/child.hpp"
#include "toolchain/validation/unit_test.hpp"

using namespace Toolchain::Validation;

static const char* fixture;
static Harness Processes = {.name = "Validation::Process"};

VALIDATION_TEST(Processes, binary_roundtrip) {
  unsigned char data[256 * 1024];
  for (size_t i = 0; i < sizeof(data); ++i) {
    data[i] = i;
  }
  const Bytes args[] = {bytes("echo")};
  Process::Request request = {
    .executable = bytes(fixture),
    .arguments = args,
    .argument_count = 1,
    .standard_input = {data, sizeof(data)}};
  auto observed = Process::run(request);
  Process::Expectation expected = {
    .exit_status = 7,
    .standard_input = request.standard_input,
    .standard_output = request.standard_input,
    .standard_error = request.standard_input};
  EXPECT(Process::compare(observed, expected) == Process::Difference::None);

  Process::Observation moved(static_cast<Process::Observation&&>(observed));
  EXPECT(!observed.standard_output.data);
  EXPECT_HEX(moved.standard_output, request.standard_input);
}

VALIDATION_TEST(Processes, argument_spelling) {
  const Bytes args[] = {bytes("arguments"),  bytes(""),
                        bytes("with space"), bytes("a\"b"),
                        bytes("trailing\\"), bytes("\xc3\xa9")};
  Process::Request request = {
    .executable = bytes(fixture), .arguments = args, .argument_count = 6};
  auto observed = Process::run(request);
  const char expected[] = "\0with space\0a\"b\0trailing\\\0\xc3\xa9";
  EXPECT(!observed.runner_error);
  EXPECT_EQ(observed.exit_status, 0);
  EXPECT_HEX(observed.standard_output, (Bytes{expected, sizeof(expected)}));
}

VALIDATION_TEST(Processes, deadline_termination) {
  const Bytes args[] = {bytes("timeout")};
  Process::Request request = {
    .executable = bytes(fixture),
    .arguments = args,
    .argument_count = 1,
    .timeout_nanoseconds = 20'000'000};
  auto observed = Process::run(request);
  EXPECT(!observed.runner_error);
  EXPECT(observed.timed_out);
  EXPECT_EQ(observed.exit_status, 137);
}

VALIDATION_TEST(Processes, invalid_arguments) {
  auto observed = Process::run(Process::Request{.executable = {}});
  EXPECT(observed.runner_error);
  EXPECT(!observed.launched);
}

int main(int argc, const char* argv[]) {
  if (argc != 2) {
    return 1;
  }
  fixture = argv[1];
  return Test::run(1, argv);
}
