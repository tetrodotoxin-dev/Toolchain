// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#include "consumer/application/value.h"

#include "consumer/base/value.h"

S32 consumer_value(S32 value) {
  return consumer_base(value) + 1;
}
