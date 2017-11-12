module pierce.controllers.users;

import core.time;
import dpq2.exception;
import dpq2;
import std.array : array;
import std.algorithm.iteration : map;
import std.traits;
import std.typecons;
import std.uuid;
import url;
import vibe.d;

import pierce.db;
import pierce.domain;
import pierce.feeds;
import pierce.vibeutil;

class UsersControllerImpl
{
    Json getSelf(User user)
    {
        Json js = Json.emptyObject;
        js["id"] = user.id.toString;
        js["email"] = user.email;
        js["checkIntervalSeconds"] = cast(int) user.checkInterval.total!"seconds";
        return js;
    }

    Json postDelete(User user)
    {
        Json js = Json.emptyObject;
        return js;
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
            js["setPassword"] = true;
            user.setPassword(newPassword);
        }
        else
        {
            js["setPassword"] = false;
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

    Json getSubscriptions(User user)
    {
        auto js = Json.emptyObject;
        js["subscriptions"] =
            query!Subscription(`SELECT * FROM subscriptions WHERE userId = $1`, user.id.toString)
            .map!(x => x.toJson)
            .array;
        return js;
    }
}
