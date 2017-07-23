module pierce.vibeutil;

import vibe.d;
import std.traits;
import std.uuid;

import pierce.db;
import pierce.domain;

class AuthedBase
{
    import std.typecons : Nullable;
    protected Nullable!User checkAuth(HTTPServerRequest req, HTTPServerResponse resp)
    {
        auto s = req.cookies[COOKIE_NAME];
        if (!s)
        {
            return Nullable!User.init;
        }
        auto p = s in sessions;
        if (!p)
        {
            return Nullable!User.init;
        }
        auto id = parseUUID(*p);
        return fetch!User(id);
    }
}

template Authed(TController, string myPath)
{
    import std.traits;

    @path(myPath)
    class Authed : AuthedBase
    {
        TController _parent = new TController;
        mixin(authedForwardClass!TController);
    }
}

string authedForwardClass(TController)()
{
    auto s = ``;
    foreach (name; __traits(derivedMembers, TController))
    {
        foreach (method; __traits(getOverloads, TController, name))
        {
            auto k = authedForwardMethod!(name, method);
            s ~= k;
        }
    }
    return s;
}

import std.traits;
string authedForwardMethod(string fnName, alias method)()
{
    auto s = ReturnType!(method).stringof
        ~ ` `
        ~ fnName
        ~ `(HTTPServerRequest reqForAuth, HTTPServerResponse respForAuth`;
    foreach (i, p; Parameters!method)
    {
        if (!is(p == User))
        {
            auto istr = i.to!string;
            s ~= `, `;
            s ~= p.stringof;
            s ~= ` arg`;
            s ~= istr;
        }
    }
    s ~= `)
    {
        try
        {
            auto user = checkAuth(reqForAuth, respForAuth);
            if (user.isNull)
            {
                respForAuth.statusCode = 401;
                return typeof(return).init;
            }
            return _parent.`;

    s ~= fnName;
    s ~= `(`;
    foreach (i, p; Parameters!method)
    {
        if (i > 0)
        {
            s ~= `, `;
        }
        if (is(p : User))
        {
            s ~= `user`;
        }
        else
        {
            s ~= `arg`;
            s ~= i.to!string;
        }
    }
    s ~= `);
        }
        catch (Throwable e)
        {
            logError("unexpected error %s", e);
            respForAuth.statusCode = 500;`;
    static if (is(ReturnType!method == Json))
    {
        s ~= `
            auto retFromAuth = Json.emptyObject();
            retFromAuth["error"] = e.toString();
            retFromAuth["success"] = false;
            return retFromAuth;`;
    }
    else
    {
        s ~= `
            return ` ~ ReturnType!(method).stringof ~ `.init;`;
    }
    s ~= `
        }
    }

    `;
    return s;
}



enum COOKIE_NAME = "sessionToken";

// TODO: expire people at the right times
// TODO: consider putting sessions in the database
shared string[string] sessions;
