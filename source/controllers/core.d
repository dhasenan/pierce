module pierce.controllers.core;

import std.experimental.logger;
import std.traits;
import std.uuid;
import vibe.d;

import pierce.db;
import pierce.domain;

alias Sess = pierce.domain.Session;

class AuthedBase
{
    import std.typecons : Nullable;
    protected Nullable!User checkAuth(HTTPServerRequest req, HTTPServerResponse resp)
    {
        auto sp = req.cookies.get(COOKIE_NAME, "");
        if (sp == "")
        {
            infof("missing cookie %s", COOKIE_NAME);
            return Nullable!User.init;
        }
        auto sessionId = parseUUID(sp);
        auto maybeSession = fetch!Sess(sessionId);
        if (maybeSession.isNull)
        {
            infof("failed to find session %s", sessionId);
            return Nullable!User.init;
        }
        auto session = maybeSession.get;
        if (session.expires < Clock.currTime(UTC()))
        {
            infof("session %s is already expired", sessionId);
            // clean it up I guess?
            dbdelete(session);
            return Nullable!User.init;
        }
        auto user = fetch!User(session.userId);
        if (user.isNull)
        {
            infof("user is null despite having a valid session");
        }
        return user;
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
        foreach (method; MemberFunctionsTuple!(TController, name))
        {
            if (__traits(getProtection, method) == "public")
            {
                auto k = authedForwardMethod!(name, method);
                s ~= k;
            }
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

    auto params = [ParameterIdentifierTuple!method];
    foreach (i, p; Parameters!method)
    {
        if (!is(p == User))
        {
            auto istr = i.to!string;
            s ~= `, `;
            s ~= p.stringof;
            s ~= ` `;
            s ~= params[i];
        }
    }
    s ~= `)
    {
        try
        {
            auto user = checkAuth(reqForAuth, respForAuth);
            if (user.isNull)
            {
                infof("not logged in person!!1");
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
            s ~= params[i];
        }
    }
    s ~= `);
        }
        catch (Throwable e)
        {
            errorf("unexpected error %s", e);
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
