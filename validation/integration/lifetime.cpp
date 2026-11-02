// # Toolchain
// Copyright (c) 2023-present Matt Kaes and contributors

#ifdef LIFETIME_STANDARD_FIRST
#include <atomic>
#include <new>
#endif

#include "toolchain/memory/lifetime.hpp"

#ifdef LIFETIME_STANDARD_AFTER
#include <atomic>
#include <new>
#endif

using namespace Toolchain::Memory;

#if !defined(LIFETIME_STANDARD_FIRST) && !defined(LIFETIME_STANDARD_AFTER)
#if defined(_NEW) || defined(_NEW_) || defined(_LIBCPP_NEW)
#error "Lifetime must remain independent of C++ library headers."
#endif
#endif

struct Value {
  S32 value;
  constexpr Value(S32 value) : value(value) {}
  Value(const Value&) = delete;
  Value(Value&&) = delete;
};

union Storage {
  S32 number;
  Value value;
  constexpr Storage() {}
  constexpr ~Storage() {}
};

constexpr auto construct(S32 expected) -> bool {
  Storage storage;
  S32 calls = 0;
  auto& number = Lifetime::construct<S32>(&storage.number);
  if (number != 0) {
    return false;
  }

  auto& value = Lifetime::construct<Value>(&storage.value, [&] {
    ++calls;
    return Value(expected);
  });

  const bool correct = value.value == expected && calls == 1;
  value.~Value();
  return correct;
}

static_assert(construct(42));

S32 main(S32 argc, char**) {

#if defined(LIFETIME_STANDARD_FIRST) || defined(LIFETIME_STANDARD_AFTER)

  std::atomic<S32> count(argc);
  const std::nothrow_t tag;
  (void)tag;
  if (::operator new(sizeof(argc), &argc) != &argc ||
      ::operator new[](sizeof(argc), &argc) != &argc || count.load() != argc) {
    return 1;
  }

  ::operator delete(&argc, &argc);
  ::operator delete[](&argc, &argc);

#endif

  return construct(argc) ? 0 : 1;
}
