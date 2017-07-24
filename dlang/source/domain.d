module pierce.domain;

import vibe.core.log;
import core.time;
import std.datetime;
import std.random;
import std.uuid;

struct User
{
    UUID id;
    string email;
    string sha;
    string pbkdf2;
    Duration checkInterval;
}

struct Feed
{
    UUID id;
    string url;
    string title;
    string iconURL;

    Duration checkInterval;
    SysTime nextRead;
    SysTime lastRead;
    int errors;
}

struct Article
{
    UUID id;
    UUID feedId;
    string url;
    string title;
    string description;
    string author;
    string internalId;
    SysTime publishDate;
}

struct Subscription
{
    UUID userId;
    UUID feedId;
    string title;
    string labels;
}

Json toJson(T)(T value)
{
    return Json.emptyObject;
}

bool checkPassword(const User user, string password)
{
    import kdf.pbkdf2;
    import std.digest.sha;
    import std.digest.digest : toHexString;
    import std.string : representation;

    if (user.pbkdf2)
    {
        import std.conv : to;
        import std.string : split;
        import std.algorithm.iteration : splitter;

        auto a = splitter(user.pbkdf2, ":");
        auto rounds = a.front.to!uint;
        a.popFront;
        ubyte[] salt = a.front.fromHexString;
        a.popFront;
        ubyte[] hash = a.front.fromHexString;
        ubyte[] expected = pbkdf2(password.representation, salt, rounds);
        bool eq = true;
        foreach (i, h; hash)
        {
            // need stronk password handling!
            eq &= (h == expected[i]);
        }
        return eq;
    }
    else if (user.sha)
    {
        auto sha = password.representation.sha1Of.toHexString;
        return sha == user.sha;
    }
    else
    {
        logError("user %s has no password", user.email);
        return false;
    }
}

ubyte[] fromHexString(const char[] c)
{
    ubyte[] b = new ubyte[c.length / 2];
    for (uint i = 0; i < b.length; i++)
    {
        import std.conv : to;
        auto j = i * 2;
        b[i] = to!ubyte(c[j .. j+1], 16);
    }
    return b;
}

void setPassword(ref User user, string password)
{
    import kdf.pbkdf2;
    import std.digest.sha;
    import std.digest.digest : toHexString;
    import std.string : representation;
    import std.format : format;

    user.sha = null;
    ubyte[16] salt;
    uint rounds = 4096;
    foreach (ref ubyte b; salt) b = uniform!ubyte();
    ubyte[] hash = pbkdf2(password.representation, salt, rounds);
    user.pbkdf2 = format(
            "%s:%s:%s",
            rounds,
            salt.toHexString,
            hash.toHexString);
}
