module pierce.app;

import vibe.d;

import pierce.domain;

shared static this()
{
    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    auto router = new URLRouter;
    router.registerWebInterface(new Authed!(FeedsControllerImpl, "feeds"));
    listenHTTP(settings, router);
}

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
    res.bodyWriter.write("nope");
}

class AuthedBase
{
    import std.typecons : Nullable;
    protected Nullable!User checkAuth(HTTPServerRequest req, HTTPServerResponse resp)
    {
        return Nullable!User.init;
    }
}

template Authed(TController, string path)
{
    import std.traits;

    class Authed : AuthedBase
    {
        TController _parent;
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
        auto user = checkAuth(reqForAuth, respForAuth);
        if (user.isNull) return Json.init;
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

    `;
    return s;
}

class FeedsControllerImpl
{
    Json postAdd(User user, string url, string title, string labels)
    {
        return Json.init;
    }

    Json postUnsubscribe(User user, string id)
    {
        return Json.init;

    }

    Json postRead(User user, string id)
    {

        return Json.init;
    }

    Json postUpdate(User user, string id, string title, int checkIntervalSeconds, string labels)
    {

        return Json.init;
    }

    Json postMarkUnread(User user, string feedId, string articleId)
    {

        return Json.init;
    }

    Json postMarkRead(User user, string feedId, string articleId)
    {

        return Json.init;
    }

    Json postMarkOlderRead(User user, string feedId, string articleId)
    {

        return Json.init;
    }

    Json getNewer(User user, string id, string lastRead)
    {
        return Json.init;
    }

    Json getChunk(User user, string feedId, string chunkId)
    {
        return Json.init;
    }

    Json getAll(User user)
    {
        return Json.init;
    }
}

// This would better be named "not-logged-in controller"
class LoginController
{
    enum LOGIN_DURATION = dur!"days"(14);

    // Do you a login for great good!
    Json login(HTTPServerResponse response, string email, string password)
    {
        string[1] args;
        args[0] = email;
        auto matches = db.query!User(`SELECT * FROM "user" WHERE email = $1`, args);
        if (matches.length > 1)
        {
            log.errorf("multiple users match email %s", email);
        }
        foreach (match; matches)
        {
            if (match.checkPassword(password))
            {
                auto sessionTag = randomUUID.toString;
                sessions[sessionTag] = match.id.toString;
                Cookie cookie;
                cookie.name = COOKIE_NAME;
                cookie.value = sessionTag;
                auto expDate = Clock.currTime + LOGIN_DURATION;
                cookie.expires = expDate.toRFC822DateTimeString;
                cookie.path = "/";
                response.setCookie(cookie);
            }
        }
    }

    Json register(HTTPServerResponse response, string email, string password)
    {
        User user;
        user.email = email;
        user.setPassword(password);
        auto js = Json.emptyObject;
        try
        {
            insert(user);
        }
        catch (Dpq2Exception e)
        {
            // TODO detect exact exception for conflict
            log.errorf("failed to save user: %s", e);
            responses.statusCode = 409;
            js["success"] = false;
            js["error"] = "Another person registered with that email address already.";
            return js;
        }
        js["success"] = true;
        js["id"] = user.id.toString;
        return js;
    }

    void logout(HTTPServerRequest req, HTTPServerResponse response)
    {
        // Clear the cookie: set its value to something invalid, set it to expire
        Cookie cookie;
        cookie.name = COOKIE_NAME;
        cookie.value = "invalid";
        // Date doesn't matter if it's in the past.
        cookie.expires = "Wed, 21 Oct 2015 07:28:00 GMT";
        cookie.path = "/";
        cookie.maxAge = 1;
        response.setCookie(cookie);
        response.writeVoidBody();
    }
}

class UsersController
{
    User get(User user)
    {
        // We don't want to show everyone your password hash.
        user.sha = null;
        user.pbkdf2 = null;
        return user;
    }

    Json update(
            HTTPServerResponse res,
            User user,
            string email,
            string oldPassword,
            string newPassword,
            int checkIntervalSeconds)
    {
        auto js = Json.emptyObject;
        if (!user.checkPassword(oldPassword))
        {
            res.statusCode = 401;
            js["success"] = false;
            js["error"] = "Current password does not match";
            return js;
        }

        // optimism
        js["success"] = true;
        // TODO min password length?
        if (newPassword.length)
        {
            js["setPassword"] = false;
            user.setPassword(newPassword);
        }
        else
        {
            js["setPassword"] = true;
        }
        user.email = email;
        user.checkIntervalSeconds = checkIntervalSeconds;
        try
        {
            update(user);
        }
        catch (Dpq2Exception e)
        {
            // TODO detect exact exception for conflict
            log.errorf("failed to save user: %s", e);
            responses.statusCode = 409;
            js["success"] = false;
            js["setPassword"] = false;
            js["error"] = "Another person registered with that email address already.";
            return js;
        }

        return js;
    }
}

enum COOKIE_NAME = "sessionToken";

// TODO: expire people at the right times
// TODO: consider putting sessions in the database
shared string[string] sessions;
