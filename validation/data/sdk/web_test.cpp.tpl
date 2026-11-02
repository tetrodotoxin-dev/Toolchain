// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/test.hpp"

#include "consumer/application/value.h"

using namespace Toolchain::Validation;

static Harness WebValidation = {
  .name = "Web validation",
};

VALIDATION_TEST(WebValidation, executes) {
  EXPECT_EQ(consumer_value(S32(41)), S32(42));
}
