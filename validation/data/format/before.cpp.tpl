#include "example/module/value.hpp"
#include "foundation/value.hpp"
#include <stdint.h>
#include "toolchain/export.h"
#include "runtime/value.hpp"
#include <stdio.h>
#include "alpha/value.hpp"

using namespace Example::Module;

uint32_t count=0;

auto increment(uint32_t value)->uint32_t{value++;if(value){value++;}return value;}

const char* text="using namespace Example::Module::Detail;";
