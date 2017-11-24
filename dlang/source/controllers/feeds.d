module pierce.controllers.feeds;

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

import pierce.db;
import pierce.domain;
import pierce.feeds;
import pierce.controllers.core;

class FeedsControllerImpl
{
    Json postAdd(User user, string url, string title, string labels)
    {
        auto js = Json.emptyObject;
        // Let's have a little optimism here.
        js["success"] = true;


        infof("checking URL for feeds");
        Feed[] feeds = query!Feed("select * from feeds where url = $1", url);
        if (feeds.length >= 1)
        {
            return makeSub(user, feeds[0], title, labels);
        }
        try
        {
            feeds = findFeedForURL(url);
        }
        catch (Exception e)
        {
            errorf("while trying to find feeds at %s: %s", url, e);
            js["success"] = false;
            js["error"] = e.toString;
            return js;
        }
        infof("found %s feeds", feeds.length);
        if (feeds.length == 0)
        {
            js["success"] = false;
            js["error"] = "No feeds found on this URL";
            return js;
        }

        if (feeds.length > 1)
        {
            infof("found several");
            js["success"] = true;
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

        infof("found only one");
        Feed feed = feeds[0];
        feeds = query!Feed("select * from feeds where url = $1", feed.url);
        if (feeds.length >= 1)
        {
            feed = feeds[0];
        }
        else
        {
            insert(feed);
            infof("saved new feed");
            auto articles = fetchArticles(feed);
            foreach (article; articles)
            {
                insert(article);
            }
            infof("saved %s articles", articles.length);
        }
        return makeSub(user, feed, title, labels);
    }

    private Json makeSub(User user, Feed feed, string title, string labels)
    {
        // TODO potential race here.
        // If we create a new feed and then our cleaner task runs, we might delete the feed
        // because there are no subscribers.
        // But then we try to add a subscriber and the feed gets deleted.
        // Making this a transaction should fix that, though we'll need to add transactions to dpq2.
        auto js = Json.emptyObject;
        auto id = feed.id;
        Subscription sub;
        sub.userId = user.id;
        sub.title = title;
        sub.labels = labels;
        sub.feedId = id;
        try
        {
            insert!(Subscription, Conflict.update)(sub);
            infof("saved sub");
            js["success"] = true;
            js["added_feed"] = true;
            js["articles"] = fetchArticles(feed).map!(x => toJson(x)).array;
            js["feed_id"] = id.toString;
        }
        catch (Dpq2Exception e)
        {
            infof("error: %s", e);
            js["success"] = false;
            // Is it a conflict?
            import std.algorithm.searching : canFind;
            if (e.msg.canFind("duplicate key"))
            {
                js["already_subscribed"] = true;
            }
            else
            {
                errorf("while trying to grab feed from %s for user %s", feed.url, user.id);
                js["error"] = e.toString;
            }
        }

        return js;
    }

    // We need to label this package so that getOverloads can look at it and determinet that it's
    // not public. __traits(getOverloads) sucks.
    package Feed[] findFeedForURL(string url)
    {
        infof("querying for existing feed");
        auto existing = query!Feed("select * from feeds where url = $1", url);
        Feed feedToAdd;
        if (existing.length)
        {
            infof("found %s existing feeds", existing.length);
            return existing;
        }
        infof("looking for feeds at %s", url);
        auto feeds = findFeeds(url.parseURL);
        infof("found %s feeds", feeds.length);
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

    Json getMine(User user)
    {
        auto feeds = query!Feed(`
            SELECT feeds.* FROM feeds
            INNER JOIN subscriptions ON subscriptions.feedId = feeds.id
            WHERE subscriptions.userId = $1`, user.id.toString);
        auto js = Json.emptyObject;
        auto fa = Json.emptyArray;
        foreach (f; feeds) fa ~= f.toJson;
        js["feeds"] = fa;
        return js;
    }

    Json postUnsubscribe(User user, string id)
    {
        deleteSub(user, id);
        return Json.emptyObject;
    }

    Json postUpdate(User user, string id, string title, int checkIntervalSeconds, string labels)
    {
        return Json.init;
    }

    Json postMarkUnread(User user, string feedId, string articleId)
    {
        markUnread(user, feedId, articleId);
        return Json.emptyObject;
    }

    Json postMarkRead(User user, string feedId, string articleId)
    {
        markRead(user, feedId, articleId);
        return Json.emptyObject;
    }

    Json postMarkOlderRead(User user, string feedId, string articleId)
    {
        markOlderRead(user, feedId, articleId);
        return Json.emptyObject;
    }

    Json getNewer(User user, string id, string lastRead)
    {
        auto js = Json.emptyObject;
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

    Json getArticles(User user, bool unreadOnly = false, string newerThan = null, string olderThan = null)
    {
        // psql supports years from -4713 to 294276
        // this is a narrower range, but it's more than reasonable
        // (mysql supports 1000 to 9999, for no discernable reason)
        if (!newerThan)
        {
            newerThan = "1000-01-01T00:00:00Z";
        }
        if (!olderThan)
        {
            olderThan = "9999-01-01T00:00:00Z";
        }
        auto js = Json.emptyObject;
        js["articles"] = query!Article(`
                SELECT
                    articles.*,
                    EXISTS (
                        SELECT * FROM read
                        WHERE read.articleId = articles.id
                        AND read.feedId = articles.feedId
                        AND read.userId = $1
                    ) AS isRead
                FROM articles
                INNER JOIN subscriptions ON subscriptions.feedId = articles.feedId
                WHERE subscriptions.userId = $1
                AND articles.publishDate > $2::timestamp
                AND articles.publishDate < $3::timestamp
                ORDER BY publishDate DESC
                LIMIT 500`,
                user.id.toString(), newerThan, olderThan, unreadOnly.to!string)
            .map!(x => toJson(x))
            .array;
        return js;
    }

    Json getAll(User user, string newerThan, string olderThan)
    {
        if (!newerThan)
        {
            newerThan = "1970-01-01T00:00:00Z";
        }
        auto js = Json.emptyObject;
        js["articles"] = query!Article(`
                SELECT articles.* FROM articles
                INNER JOIN subscriptions ON subscriptions.feedId = articles.feedId
                WHERE subscriptions.userId = $1
                AND articles.readDate > $2
                ORDER BY readDate ASCENDING
                LIMIT 500`,
                user.id.toString, newerThan)
            .map!(x => toJson(x))
            .array;
        return js;
    }
}


