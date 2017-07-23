module pierce.app;

import vibe.d;
import dpq2;
import dpq2.exception;
import core.time;
import std.traits;
import std.typecons;
import std.uuid;

import pierce.domain;
import pierce.db;
import pierce.vibeutil;

shared static this()
{
    logInfo(updateText!User);
    logInfo(insertText!User);
    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    auto router = new URLRouter;
    router.get("static/*", serveStaticFiles("static/"));
    router.get("/", serveStaticFile("static/index.html"));
    router.registerWebInterface(new Authed!(FeedsControllerImpl, "feeds"));
    router.registerWebInterface(new Authed!(UsersControllerImpl, "users"));
    router.registerWebInterface(new LoginController);
    listenHTTP(settings, router);
}

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
    res.bodyWriter.write("nope");
}

class FeedsControllerImpl
{
    Json postAdd(User user, string url, string title, string labels)
    {
        auto existing = query!Feed("select * from feeds where url = $1", url);
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

    Json getAll(User user)
    {
        return Json.init;
    }
}

struct Test
{
    UUID id;
}

// This would better be named "not-logged-in controller"
@path("login")
class LoginController
{
    enum LOGIN_DURATION = dur!"days"(14);

    // Do you a login for great good!
    Json login(HTTPServerResponse response, string email, string password)
    {
        auto js = Json.emptyObject;
        try
        {
            string[1] args;
            args[0] = email;
            auto matches = query!User(`SELECT * FROM users WHERE email = $1`, args);
            if (matches.length > 1)
            {
                logError("multiple users match email %s", email);
            }
            foreach (match; matches)
            {
                if (match.checkPassword(password))
                {
                    auto sessionTag = randomUUID.toString;
                    sessions[sessionTag] = match.id.toString;
                    Cookie cookie = new Cookie;
                    cookie.value = sessionTag;
                    auto expDate = Clock.currTime + LOGIN_DURATION;
                    cookie.expires = expDate.toRFC822DateTimeString;
                    cookie.path = "/";
                    response.cookies[COOKIE_NAME] = cookie;
                    js["success"] = true;
                    js["id"] = match.id.toString;
                    js["email"] = match.email;
                    js["checkIntervalSeconds"] = match.checkInterval.total!"seconds";
                    return js;
                }
            }
            js["success"] = false;
            return js;
        }
        catch (Throwable e)
        {
            logError("couldn't log user %s in: %s", email, e);
            response.statusCode = 500;
            js["success"] = false;
            js["error"] = e.toString();
            return js;
        }
    }

    Json register(HTTPServerResponse response, string email, string password)
    {
        logInfo("registering %s / %s", email, password);
        User user;
        user.id = randomUUID;
        user.email = email;
        user.setPassword(password);
        logInfo("set password");
        try
        {
            inConnection!(delegate immutable(Answer) (scope Connection conn) {
                QueryParams p;
                p.args = [
                    toValue(user.id.toString()),
                    toValue(user.email),
                    toValue(user.sha),
                    toValue(user.pbkdf2),
                    toValue(cast(int)user.checkInterval.total!"seconds"),
                ];
                p.sqlCommand = `INSERT INTO users (id, email, sha, pbkdf2, checkInterval) VALUES (uuid($1), $2, $3, $4, $5)`;
                return conn.execParams(p);
            })();
            logInfo("inserted");
        }
        catch (Dpq2Exception e)
        {
            // TODO detect exact exception for conflict
            logError("failed to save user: %s", e);
            response.statusCode = 409;
            auto js = Json.emptyObject;
            js["success"] = false;
            js["error"] = "Another person registered with that email address already.";
            return js;
        }
        catch (Throwable e)
        {
            logError("failed to save user: %s", e);
            response.statusCode = 500;
            auto js = Json.emptyObject;
            js["success"] = false;
            js["error"] = e.toString;
            return js;
        }
        return login(response, email, password);
    }

    void logout(HTTPServerRequest req, HTTPServerResponse response)
    {
        // Clear the cookie: set its value to something invalid, set it to expire
        auto sessionTag = req.cookies[COOKIE_NAME];
        sessions.remove(sessionTag);
        Cookie cookie = new Cookie;
        cookie.value = "invalid";
        // Date doesn't matter if it's in the past.
        cookie.expires = "Wed, 21 Oct 2015 07:28:00 GMT";
        cookie.path = "/";
        cookie.maxAge = 1;
        response.cookies[COOKIE_NAME] = cookie;
        response.writeVoidBody();
    }
}

class UsersControllerImpl
{
    Json getSelf(User user)
    {
        // The task of figuring out who you are is already handled.
        // We don't want to show everyone your password hash.
        user.sha = null;
        user.pbkdf2 = null;
        return Json.init;
    }

    Json postDelete(User user)
    {
        // We don't want to show everyone your password hash.
        user.sha = null;
        user.pbkdf2 = null;
        return Json.init;
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
        user.checkInterval = dur!"seconds"(checkIntervalSeconds);
        try
        {
            .update(user);
        }
        catch (Dpq2Exception e)
        {
            // TODO detect exact exception for conflict
            logError("failed to save user: %s", e);
            res.statusCode = 409;
            js["success"] = false;
            js["setPassword"] = false;
            js["error"] = "Another person registered with that email address already.";
            return js;
        }

        return js;
    }
}
