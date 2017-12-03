/** Because std.typecons.Nullable has a cruddy interface. */
module pierce.opt;

import std.traits : ReturnType;
public import std.typecons : Nullable, nullable;

bool present(T)(Nullable!T n)
{
    return !n.isNull;
}

auto ifPreset(alias v, T)(Nullable!T maybe)
{
    if (maybe.present)
    {
        return v(maybe.value);
    }
    return ReturnType!(v).init;
}

Nullable!T just(T)(T value)
{
    return nullable(value);
}

Nullable!T nothing(T)()
{
    return Nullable!T.init;
}
