module pierce.mongo;

import core.time;
import pierce.domain;
import std.datetime;
import std.experimental.logger;
import std.uuid;
import vibe.data.bson;

void dumpMongo(string host, ushort port)
{
    import vibe.data.json;
    import vibe.db.mongo.mongo;
    import std.stdio;

    auto client = connectMongoDB(host, port);
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

void readMongo(string host = "localhost", ushort port = 27017)
{
    inConnection!((conn) => readMongo(conn, host, port));
}

void readMongo(Connection conn, string host, ushort port)
{
    import pierce.db.core;
    import vibe.db.mongo.mongo;
    import std.random;

    // Burn it all to the ground!
    infof("have to clear away the rubble before we can build anew");
    conn.query!void("DELETE FROM users");
    conn.query!void("DELETE FROM subscriptions");
    conn.query!void("DELETE FROM feeds");
    conn.query!void("DELETE FROM articles");
    conn.query!void("DELETE FROM sessions");
    conn.query!void("DELETE FROM read");

    auto client = connectMongoDB(host, port);
    auto db = client.getDatabase("pierce");

    UUID[string] feedIds;
    UUID[string] userIds;
    bool[string] activeChunks;

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
        auto existing = conn.query!Feed("select * from feeds where url = $1", feed.url);
        if (existing.length > 0)
        {
            feedIds[id] = existing[0].id;
        }
        else
        {
            conn.insert(feed);
            feedIds[id] = feed.id;
        }
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
        conn.insert(user);
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
            conn.insert(sub);
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
        auto id = chunk["_id"].get!BsonObjectID.toString;
        auto archived = !(id in activeChunks);

        auto feedId = feedIds[chunk["FeedId"].str];
        foreach (mart; chunk["Articles"])
        {
            auto art = artBson(mart, feedId);
            conn.insert(art);
            if (archived)
            {
                // Mark read automatically.
                conn.query!void(`
                        INSERT INTO read (userId, feedId, articleId)
                        (
                            SELECT userId, $1, $2 FROM subscriptions
                            WHERE feedId = $1
                        )
                        ON CONFLICT DO NOTHING`,
                        feedId.toString, art.id.toString);
            }
        }
    }

    // 4. Remaining read articles.
    foreach (muser; db["users"].find)
    {
        auto user = conn.query!User("SELECT * FROM users WHERE email = $1", muser["Email"].str);
        infof("handling read articles for user %s", user[0].email);
        auto id = user[0].id.toString;
        foreach (msub; muser["Subscriptions"])
        {
            auto feedId = feedIds[msub["FeedId"].str].toString;
            foreach (read; msub["ReadArticles"])
            {
                conn.query!void(`
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
        author = mauth.get[0]["Name"].str;
    }
    Article art =
    {
        feedId: feedId,
        author: author,
        description: mart["Description"].str,
        internalId: mart["UniqueId"].str,
        mongoId: mart["_id"].get!BsonObjectID.toString,
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
    return parse(s.str, ISO8601FORMAT);
}

string str(Bson bs)
{
    if (bs.isNull) return "";
    if (bs.type == Bson.Type.objectID) return bs.get!BsonObjectID.toString;
    return bs.get!string;
}
