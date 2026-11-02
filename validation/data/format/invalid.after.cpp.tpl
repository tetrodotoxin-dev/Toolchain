#include "example/module/broken.hpp"

using namespace Example;

// The buffer stores each value.
S32 warned;

// This helper simply provides a robust solution.
S32 rejected;

S32 invalid() {
  return 1;
}

auto allocate() -> void* {
  return malloc(1);
}
