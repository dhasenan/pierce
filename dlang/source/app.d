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
import pierce.feeds;
import pierce.vibeutil;

shared static this()
{
    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    auto router = new URLRouter;
    auto fsettings = new HTTPFileServerSettings;
    fsettings.serverPathPrefix = "/static";
    router.get("/static/*", serveStaticFiles("static/", fsettings));
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
        auto js = Json.emptyObject;
        // Let's have a little optimism here.
        js["success"] = true;

        // Subscription, just in case we manage to insert it.
        Subscription sub;
        sub.userId = user.id;
        sub.title = title;
        sub.labels = labels;

        auto feeds = findFeedForURL(url);
        if (feeds.length == 0)
        {
            js["success"] = false;
            js["error"] = "No feeds found on this URL";
            return js;
        }

        if (feeds.length > 0)
        {
            auto arr = new Json[feeds.length];
            foreach (i, feed; feeds)
            {
                auto jsfeed = Json.emptyObject;
                jsfeed["title"] = feed.title;
                jsfeed["url"] = feed.url;
                arr[i] = jsfeed;
            }
            js["feeds"] = arr;
            return js;
        }

        if (feeds.length == 1)
        {
            saveOrUpdate(feeds[0]);
            auto id = feeds[0].id;
            sub.feedId = id;
            try
            {
                insert(sub);
                js["success"] = true;
                js["feed_id"] = id.toString;
            }
            catch (Dpq2Exception e)
            {
                js["success"] = false;
                // Is it a conflict?
                import std.algorithm.searching : canFind;
                if (e.msg.canFind("duplicate key"))
                {
                    js["already_subscribed"] = true;
                }
                else
                {
                    logError("while trying to grab feed from %s for user %s", url, user.id);
                    js["error"] = e.toString;
                }
            }
        }

        return js;
    }

    // We need to label this package so that getOverloads can look at it and determinet that it's
    // not public. __traits(getOverloads) sucks.
    package Feed[] findFeedForURL(string url)
    {
        auto existing = query!Feed("select * from feeds where url = $1", url);
        Feed feedToAdd;
        if (existing.length)
        {
            return existing;
        }
        else
        {
            auto feeds = findFeeds(url);
            if (feeds.length == 0)
            {
                return null;
            }
            if (feeds.length == 1)
            {
                // If I add questionablecontent.net and you add questionablecontent.net, then the
                // second one doesn't match anything, since the feed is for
                // http://www.questionablecontent.net/QCRSS.xml. So we search again.
                if (feeds[0].url != url)
                {
                    existing = query!Feed("select * from feeds where url = $1", feeds[0].url);
                    if (existing.length)
                    {
                        return existing;
                    }
                }
                return feeds;
            }
            return feeds;
        }
    }

    Json postUnsubscribe(User user, string id)
    {
        QueryParams p;
        p.sqlCommand = "DELETE FROM subscriptions WHERE userId = $1 AND feedId = $2";
        p.args = [
            toValue(user.id.toString()),
            toValue(id)
        ];
        inConnection(conn => conn.execParams(p));
        return Json.emptyObject;
    }

    Json postUpdate(User user, string id, string title, int checkIntervalSeconds, string labels)
    {
        return Json.init;
    }

    Json postMarkUnread(User user, string feedId, string articleId)
    {
        QueryParams p;
        p.sqlCommand = "DELETE FROM read WHERE userId = $1 AND feedId = $2 AND articleId = $3";
        p.args = [
            toValue(user.id.toString()),
            toValue(feedId),
            toValue(articleId),
        ];
        inConnection(conn => conn.execParams(p));
        return Json.emptyObject;
    }

    Json postMarkRead(User user, string feedId, string articleId)
    {
        QueryParams p;
        p.sqlCommand = "INSERT INTO read (userId, feedId, articleId) VALUES ($1, $2, $3)";
        p.args = [toValue(user.id.toString), toValue(feedId), toValue(articleId)];
        inConnection!(conn => conn.execParams(p));
        return Json.emptyObject;
    }

    Json postMarkOlderRead(User user, string feedId, string articleId)
    {
        QueryParams p;
        p.sqlCommand = `
            INSERT INTO read (userId, feedId, articleId)
            SELECT $1, $2, id
            FROM articles
            WHERE feedId = $2 AND publishDate <
                (SELECT publishDate FROM articles WHERE articleId = $3)`;
        p.args = [toValue(user.id.toString), toValue(feedId), toValue(articleId)];
        inConnection!(conn => conn.execParams(p));
        return Json.emptyObject;
    }

    Json getNewer(User user, string id, string lastRead)
    {
        auto js = json.emptyObject;
        js["articles"] = query!Article(`
                SELECT * FROM articles
                WHERE feedId = $1
                AND publishDate >
                    (SELECT publishDate FROM articles WHERE articleId = $2)
                ORDER BY publishDate ASCENDING
                LIMIT 500`,
                id, lastRead)
            .map!(x => toJson(x))
            .array;
        return js;
    }

    Json getAllUnread(User user, string newerThan)
    {
        if (!newerThan)
        {
            newerThan = "1970-01-01T00:00:00Z";
        }
        auto js = json.emptyObject;
        js["articles"] = query!Article(`
                SELECT articles.* FROM articles
                INNER JOIN subscriptions ON subscriptions.feedId = articles.feedId
                WHERE subscriptions.userId = $1
                AND articles.publishDate > $2
                AND NOT EXISTS
                    (SELECT * FROM read
                        WHERE readarticleId = articles.id
                        AND read.userId = $1)
                ORDER BY publishDate ASCENDING
                LIMIT 500`,
                id, newerThan)
            .map!(x => toJson(x))
            .array;
        return js;
    }

    Json getAll(User user, string newerThan)
    {
        if (!newerThan)
        {
            newerThan = "1970-01-01T00:00:00Z";
        }
        auto js = json.emptyObject;
        js["articles"] = query!Article(`
                SELECT articles.* FROM articles
                INNER JOIN subscriptions ON subscriptions.feedId = articles.feedId
                WHERE subscriptions.userId = $1
                AND articles.publishDate > $2
                ORDER BY publishDate ASCENDING
                LIMIT 500`,
                id, newerThan)
            .map!(x => toJson(x))
            .array;
        return js;
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
                    return reallyLogin(response, match, password);
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

    private Json reallyLogin(HTTPServerResponse response, User match, string password)
    {
        if (match.sha !is null)
        {
            // Old imported account. Fix!
            match.setPassword(password);
            update(match);
        }

        // Build a session
        auto sessionTag = randomUUID.toString;
        sessions[sessionTag] = match.id.toString;

        // Set session cookie
        Cookie cookie = new Cookie;
        cookie.value = sessionTag;
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
        User user;
        user.id = randomUUID;
        user.email = email;
        user.setPassword(password);
        try
        {
            saveUser(user);
            logInfo("registered %s", email);
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
                    logInfo("duplicate user %s", user.email);
                    response.statusCode = 409;
                    js["error"] = "Another person registered with that email address already.";
                    return js;
                }
            }
            logError("failed to save user %s: %s", user.email, e);
            response.statusCode = 500;
            js["error"] = e.toString;
            return js;
        }
        return reallyLogin(response, user, password);
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
}
