#pragma once
namespace Example::Module {
// Value retains one unsigned scalar and exposes read access through get_value.
// Its private storage keeps construction and observation on the same object.
class Value {public:
Value()=default;
auto get_value() const->U32{return value;}
private:
U32 value=0;
};
}
