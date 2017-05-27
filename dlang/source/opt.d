module pierce.opt;

import std.traits : ReturnType;

struct Maybe(T)
{
    T value;
    bool present;
}

auto ifPreset(alias v, T)(Maybe!T maybe)
{
    if (maybe.present)
    {
        return v(maybe.value);
    }
    return ReturnType!(v).init;
}

Maybe!T just(T)(T value)
{
    return Maybe!T(value, true);
}

Maybe!T nothing(T)()
{
    return Maybe!T(T.init, false);
}
