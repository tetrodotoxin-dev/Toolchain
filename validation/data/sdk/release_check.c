// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "consumer/application/value.h"

S32 main(void) {
  return consumer_value(41) == 42 ? 0 : 1;
}
