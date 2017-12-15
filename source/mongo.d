module pierce.mongo;

import core.time;
import vibe.db.postgresql : LockedConnection, __Conn;
import pierce.config;
import pierce.domain;
import std.datetime;
import std.experimental.logger;
import std.uuid;
import vibe.data.bson;

void dumpMongo()
{
    import vibe.data.json;
    import vibe.db.mongo.mongo;
    import std.stdio;

    auto client = connectMongoDB(config.mongo.host, config.mongo.port);
    auto db = client.getDatabase("pierce");

    foreach (collection; ["users", "feeds", "chunks"])
    {
        // Outputting json-per-line format.
        auto file = File(collection ~ ".json", "w");
        foreach (Bson item; db[collection].find)
        {
            file.write(item.toJson.toString);
            file.write("\n");
        }
    }
}

import pierce.db.core;
void readMongo()
{
    inConnection!((conn) {
        conn.queryConn!void("BEGIN");
        readMongoConn(conn);
        conn.queryConn!void("END");
        return null;
    });
}
void readMongoConn(ref scope LockedConnection!__Conn conn)
{
    import vibe.db.mongo.mongo;
    import std.random;

    // Burn it all to the ground!
    infof("have to clear away the rubble before we can build anew");
    conn.queryConn!void("DELETE FROM users");
    conn.queryConn!void("DELETE FROM subscriptions");
    conn.queryConn!void("DELETE FROM feeds");
    conn.queryConn!void("DELETE FROM articles");
    conn.queryConn!void("DELETE FROM sessions");
    conn.queryConn!void("DELETE FROM read");

    auto client = connectMongoDB(config.mongo.host, config.mongo.port);
    auto db = client.getDatabase("pierce");

    UUID[string] feedIds;
    UUID[string] userIds;
    bool[string] activeChunks;
    string[string] mongoFeedIdToURL;

    // 1. Feeds!
    // In mongodb, feeds are *relatively* flat.
    // Also, a lot of this data is about the processing of the feed.
    // We can omit that.
    infof("handling feeds");
    ulong i = 0;
    foreach (mongoFeed; db["feeds"].find)
    {
        i++;
        if (i % 100 == 0) infof("finished feed %s", i);
        auto id = mongoFeed["_id"].get!BsonObjectID.toString;
        Feed feed =
        {
            url: mongoFeed["Uri"].str,
            title: mongoFeed["Title"].str,
            iconURL: mongoFeed["IconUri"].str,
            // Set the next read time to something random in the next hour
            // so we don't have too much clustering.
            nextRead: Clock.currTime(UTC()) + uniform(0, 3600).seconds,
        };
        mongoFeedIdToURL[id] = feed.url;
        auto existing = conn.queryConn!Feed("select * from feeds where url = $1", feed.url);
        if (existing.length > 0)
        {
            feedIds[id] = existing[0].id;
        }
        else
        {
            conn.insertConn(feed);
            feedIds[id] = feed.id;
        }
        /*
        foreach (mart; mongoFeed["Articles"])
        {
            auto art = artBson(mart, feedId);
            conn.insertConn(art);
        }
        */
        activeChunks[mongoFeed["HeadChunkId"].str] = true;
    }

    // 2. Users.
    foreach (muser; db["users"].find)
    {
        User user =
        {
            email: muser["Email"].str,
            sha: muser["PasswordHash"].str,
            checkInterval: parseDuration(muser["DefaultCheckInterval"].str),
        };
        infof("handling user %s", user.email);
        conn.insertConn(user);
        foreach (msub; muser["Subscriptions"])
        {
            import std.array : Appender;
            Appender!string labels;
            foreach (size_t i, mlab; msub["Labels"])
            {
                if (i > 0) labels ~= ",";
                labels ~= mlab.str;
            }
            Subscription sub =
            {
                userId: user.id,
                feedId: feedIds[msub["FeedId"].str],
                title: msub["Title"].str,
                labels: labels.data,
            };
            conn.insertConn(sub);
        }
    }

    // 3. Articles.
    // We put this here so it's easier to mark archived articles as read.
    infof("migrating articles");
    i = 0;
    foreach (chunk; db["chunks"].find)
    {
        i++;
        if (i % 100 == 0) infof("handling chunk %s", i);
        auto id = chunk["_id"].str;
        auto archived = !(id in activeChunks);
        /*
        if (archived)
        {
            infof("skipping archived chunk %s for speed purposes", id);
            continue;
        }
        */

        UUID feedId;
        auto mid = chunk["FeedId"].str;
        if (auto p = mid in feedIds)
        {
            feedId = *p;
        }
        else
        {
            warningf("chunk %s references missing feed %s; skipping", id, mid);
            continue;
        }
        ulong count = 0;
        foreach (mart; chunk["Articles"])
        {
            count++;
            auto art = artBson(mart, feedId);
            conn.insertConn(art);
            if (archived)
            {
                // Mark read automatically.
                conn.queryConn!void(`
                        INSERT INTO read (userId, feedId, articleId)
                        (
                            SELECT userId, $1, $2 FROM subscriptions
                            WHERE feedId = $1
                        )
                        ON CONFLICT DO NOTHING`,
                        feedId.toString, art.id.toString);
            }
        }
        infof("feed %s chunk %s archived %s articles %s", feedId, id, archived, count);
    }

    // 4. Remaining read articles.
    foreach (muser; db["users"].find)
    {
        auto user = conn.queryConn!User("SELECT * FROM users WHERE email = $1", muser["Email"].str);
        infof("handling read articles for user %s", user[0].email);
        auto id = user[0].id.toString;
        foreach (msub; muser["Subscriptions"])
        {
            auto feedId = feedIds[msub["FeedId"].str].toString;
            foreach (read; msub["ReadArticles"])
            {
                conn.queryConn!void(`
                        INSERT INTO read (userId, feedId, articleId)
                        SELECT $1, $2, articles.id
                        FROM articles
                        WHERE mongoId = $3
                        ON CONFLICT DO NOTHING`,
                        id, feedId, read.str);
            }
        }
    }
    infof("done migrating");
}

private Article artBson(Bson mart, UUID feedId)
{
    string author;
    auto mauth = mart.tryIndex("Authors");
    if (!mauth.isNull)
    {
        auto mm = mauth.get;
        if (mm.type == Bson.Type.array)
        {
            mm = mm[0];
        }
        if (mm.type == Bson.Type.object)
        {
            mm = mm["Name"];
        }
        if (mm.type == Bson.Type.string)
        {
            author = mm.str;
        }
    }
    Article art =
    {
        feedId: feedId,
        author: author,
        description: mart["Description"].str,
        internalId: mart["UniqueId"].str,
        mongoId: mart["_id"].str,
        publishDate: sysDate(mart["PublishDate"]),
        title: mart["Title"].str,
        url: mart["Link"].str,
        readDate: Clock.currTime(UTC()),
    };
    return art;
}

Duration parseDuration(string s)
{
    return 30.seconds;
}

SysTime sysDate(Bson s)
{
    import pierce.datetimeformat;
    if (s.type == Bson.Type.string)
    {
        return parse(s.str, ISO8601FORMAT);
    }
    return s.get!BsonDate.toSysTime;
}

string str(Bson bs)
{
    if (bs.isNull) return "";
    if (bs.type == Bson.Type.objectID) return bs.get!BsonObjectID.toString;
    return bs.get!string;
}
