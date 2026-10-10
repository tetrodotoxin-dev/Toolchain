// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#pragma once

#include "toolchain/memory/lifetime.hpp"
#include "toolchain/toolchain.h"

// Bool fixes boolean storage at one byte while preserving the language's
// boolean expressions. True and False retain that type through deduction.
struct Bool {
  constexpr Bool() : value(false) {}
  constexpr Bool(bool value) : value(value) {}
  constexpr explicit operator bool() const { return value; }
  constexpr auto operator==(Bool rhs) const -> Bool {
    return value == rhs.value;
  }

  constexpr auto operator!=(Bool rhs) const -> Bool {
    return value != rhs.value;
  }

  constexpr auto operator|(Bool rhs) const -> Bool { return value | rhs.value; }
  constexpr auto operator&(Bool rhs) const -> Bool { return value & rhs.value; }
  constexpr auto operator^(Bool rhs) const -> Bool { return value ^ rhs.value; }
  constexpr auto operator!() const -> Bool { return !value; }
  constexpr auto operator&=(Bool rhs) -> Bool& {
    value &= rhs.value;
    return *this;
  }

  constexpr auto operator|=(Bool rhs) -> Bool& {
    value |= rhs.value;
    return *this;
  }

  constexpr auto sign() const -> S64 { return value ? 1 : -1; }
  U8 value;
};

constexpr Bool True = Bool(true);
constexpr Bool False = Bool(false);

static_assert(sizeof(Bool) == 1);
