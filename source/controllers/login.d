module pierce.controllers.login;

import core.time;
import dpq2.exception;
import dpq2;
import std.array : array;
import std.algorithm.iteration : map;
import std.experimental.logger;
import std.traits;
import std.typecons;
import std.uuid;
import url;
import vibe.d;

import pierce.config : config;
import pierce.db;
import pierce.domain;
import pierce.feeds;
import pierce.controllers.core;

alias Session = pierce.domain.Session;

immutable SESSION_DURATION = 14.days;

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
            infof("found %s users matching email %s", matches.length, email);
            if (matches.length > 1)
            {
                errorf("multiple users match email %s", email);
            }
            foreach (match; matches)
            {
                if (match.checkPassword(password))
                {
                    return reallyLogin(response, match, password);
                }
            }
            infof("no match");
            response.statusCode = 403;
            js["success"] = false;
            return js;
        }
        catch (Throwable e)
        {
            errorf("couldn't log user %s in: %s", email, e);
            response.statusCode = 500;
            js["success"] = false;
            js["error"] = e.toString();
            return js;
        }
    }

    private Json reallyLogin(HTTPServerResponse response, User match, string password)
    {
        if (match.sha !is null)
        {
            // Old imported account. Fix!
            match.setPassword(password);
            update(match);
        }

        // Build a session
        Session session =
        {
            id: randomUUID(),
            userId: match.id,
            expires: Clock.currTime(UTC()) + SESSION_DURATION,
        };
        insert(session);
        infof("set session %s => user %s", session.id, match.id);

        // Set session cookie
        Cookie cookie = new Cookie;
        cookie.value = session.id.to!string;
        auto expDate = Clock.currTime + LOGIN_DURATION;
        cookie.expires = expDate.toRFC822DateTimeString;
        cookie.path = "/";
        response.cookies[COOKIE_NAME] = cookie;

        // Make a response
        auto js = Json.emptyObject;
        js["success"] = true;
        js["id"] = match.id.toString;
        js["email"] = match.email;
        js["checkIntervalSeconds"] = match.checkInterval.total!"seconds";
        return js;
    }

    Json register(HTTPServerResponse response, string email, string password)
    {
        if (!config.allowRegistrations)
        {
            auto js = Json.emptyObject;
            js["registrationsAllowed"] = false;
            js["error"] = "New registrations have been disabled by the administrator. " ~
                "If you are the administrator, change the 'allowRegistrations' entry " ~
                "in the config file.";
            return js;
        }
        User user;
        user.id = randomUUID;
        user.email = email;
        user.setPassword(password);
        try
        {
            saveUser(user);
            infof("registered %s", email);
        }
        catch (Throwable e)
        {
            auto js = Json.emptyObject;
            js["success"] = false;
            if (auto p = cast(Dpq2Exception)e)
            {
                import std.algorithm.searching : canFind;
                if (p.msg.canFind("duplicate key"))
                {
                    infof("duplicate user %s", user.email);
                    response.statusCode = 409;
                    js["error"] = "Another person registered with that email address already.";
                    return js;
                }
            }
            errorf("failed to save user %s: %s", user.email, e);
            response.statusCode = 500;
            js["error"] = e.toString;
            return js;
        }
        return reallyLogin(response, user, password);
    }

    void logout(HTTPServerRequest req, HTTPServerResponse response)
    {
        // Clear the cookie: set its value to something invalid, set it to expire
        auto sessionTag = req.cookies.get(COOKIE_NAME, "");
        if (sessionTag != "")
        {
            try
            {
                // TODO should we really delete these or just expire them?
                // Might be nice to have this sort of info...
                dbdelete!Session(parseUUID(sessionTag));
            }
            catch (Exception e)
            {
                // This is either the database not finding it,
                // an invalid session already,
                // or something strange.
                // I'm not entirely sure how to disambiguate, but it's not a problem.
                // Probably.
                infof("unexpected error logging you out from %s: %s", sessionTag, e);
            }
        }
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

