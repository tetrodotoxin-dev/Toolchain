// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/test.hpp"

using namespace Toolchain::Validation;

static Harness WebValidation = {
  .name = "Web validation",
};

VALIDATION_TEST(WebValidation, executes) {
  EXPECT_EQ(U32(20) + U32(22), U32(42));
}
