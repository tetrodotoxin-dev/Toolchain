// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "toolchain/validation/test.hpp"

using namespace Toolchain::Validation;

static Harness Unavailable = {.name = "Unavailable"};

VALIDATION_TEST(Unavailable, feature) {
  SKIP("example unavailable feature");
}
