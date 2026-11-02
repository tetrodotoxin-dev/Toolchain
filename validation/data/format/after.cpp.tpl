#include "example/module/value.hpp"

#include <stdio.h>

#include "toolchain/export.h"

#include "runtime/value.hpp"

#include "foundation/value.hpp"

#include "alpha/value.hpp"

using namespace Example::Module;

U32 count = 0;

auto increment(U32 value) -> U32 {
  value++;
  if (value) {
    value++;
  }

  return value;
}

const char* text = "using namespace Example::Module::Detail;";
