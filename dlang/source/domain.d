module pierce.domain;

import core.time;
import pierce.datetimeformat;
import pierce.db.core : Transient;
import vibe.data.json;
import std.base64;
import std.datetime;
import std.experimental.logger;
import std.random;
import std.uuid;

static const SysTime defaultTime = SysTime(DateTime(1970, 1, 1, 0, 0, 0), UTC());

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
    SysTime nextRead = defaultTime;
    SysTime lastRead = defaultTime;
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
    SysTime publishDate = defaultTime;
    SysTime readDate = defaultTime;
    @Transient bool isRead = false;

    bool isProbablySameAs(Article other)
    {
        if (url != other.url) return false;
        if (title != other.title) return false;
        if (description != other.description) return false;
        return true;
    }
}

struct Subscription
{
    UUID userId;
    UUID feedId;
    string title;
    string labels;
}

private void addField(T, size_t i, string[] names)(T value, ref Json js)
{
    static if (i < names.length)
    {
        mixin(`auto fv = value.` ~ names[i] ~ `;`);
        auto name = names[i];
        static if (is(typeof(fv) == UUID))
        {
            js[name] = fv.toString;
        }
        else static if (is(typeof(fv) == SysTime))
        {
            js[name] = format(fv, ISO8601FORMAT);
        }
        else static if (is(typeof(fv) == Duration))
        {
            js[name] = fv.total!"seconds";
        }
        else
        {
            js[name] = fv;
        }
        addField!(T, i+1, names)(value, js);
    }
}

Json toJson(T)(T value)
{
    import std.traits : FieldNameTuple;
    Json js = Json.emptyObject;
    addField!(T, 0, [FieldNameTuple!T])(value, js);
    return js;
}

unittest
{
    Subscription s =
    {
        userId: "ee821542-c696-40f8-ae93-335bdaed288a".parseUUID,
        feedId: "a7d14ef6-ed8b-4601-9314-3170bb734e9a".parseUUID,
        title: "ikeran - always building",
        labels: "blags,mine",
    };
    auto js = s.toJson;
    assert(js["userId"].get!string == s.userId.toString);
    assert(js["feedId"].get!string == s.feedId.toString);
    assert(js["title"].get!string == s.title);
    assert(js["labels"].get!string == s.labels);
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
        ubyte[] salt = Base64.decode(a.front);
        a.popFront;
        ubyte[] hash = Base64.decode(a.front);
        ubyte[] expected = pbkdf2(password.representation, salt, rounds);
        if (expected.length != hash.length) {
            return false;
        }
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
        errorf("user %s has no password", user.email);
        return false;
    }
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
            Base64.encode(salt),
            Base64.encode(hash));
}

unittest
{
    User user;
    user.setPassword("hallelujah");
    assert(user.checkPassword("hallelujah"));
}

struct Session
{
    UUID id;
    UUID userId;
    SysTime expires = defaultTime;
}
