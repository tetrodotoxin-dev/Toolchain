// Copyright (c) 2023-present Matt Kaes and contributors

#include "validation/data/components/consumer/value.h"

#if __has_include("validation/data/components/unrelated/value.h")
#error The selected component exposes an unrelated sibling.
#endif

#if TOOLCHAIN_COMPONENT_CONSUMER_VALUE != 42
#error The selected component must receive its declared dependencies.
#endif

int main(void) {
  return 0;
}
