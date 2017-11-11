module pierce.tasks;

import dpq2;
import std.datetime;
import vibe.d;

import pierce.db;
import pierce.domain;
import pierce.feeds;

enum MAX_SAVED_ARTICLES = 1000;

void runTasks()
{
    vibe.core.core.yield();
    auto tasks = buildTasks();
    auto feedTasks = buildFeedTasks();
    logInfo("have %s periodic tasks and %s feed tasks", tasks.length, feedTasks.length);

    while (true)
    {
        logInfo("running periodic tasks");
        foreach (task; tasks)
        {
            try
            {
                logInfo("running task %s", task);
                task.run();
            }
            catch (Throwable t)
            {
                logError("in task %s: %s", task, t);
            }
        }

        auto feeds = query!Feed(`
            SELECT * FROM feeds
            WHERE nextRead IS NULL OR nextRead < now()
            ORDER BY lastRead
            LIMIT 100`);
        logInfo("scanning %s feeds", feeds.length);
        foreach (feed; feeds)
        {
            foreach (feedTask; feedTasks)
            {
                try
                {
                    logInfo("running task %s", feedTask);
                    feedTask.run(feed);
                }
                catch (Throwable t)
                {
                    logError("in feed task %s: %s", feedTask, t);
                }

            }
            feed.nextRead = Clock.currTime() + feed.checkInterval;
            update(feed);
        }
        sleep(60.seconds);
    }
}

Task[] buildTasks()
{
    return [cast(Task)new ScrubFeeds(), new ScrubReadArticles()];
}

FeedTask[] buildFeedTasks()
{
    return [
        cast(FeedTask)new ReadFeed(),
        new ScrubOldArticles(),
        // TODO feed icon finder
    ];
}

interface FeedTask
{
    void run(ref Feed feed);
}

interface Task
{
    void run();
}

class ScrubFeeds : Task
{
    void run()
    {
        QueryParams p;
        // We only delete stuff that's been read at least once to reduce data races.
        // Here, we could delete a feed with a subscriber, but it would have to be a feed that Alice
        // unsubscribed from and Bob is in the middle of subscribing to.
        // In the more common case that Alice subscribes to a unique feed, we'll skip over it
        // because it hasn't yet been read.
        p.sqlCommand = `
            DELETE FROM feeds
            WHERE lastRead IS NOT NULL
            AND NOT EXISTS (
                SELECT * FROM subscriptions
                WHERE subscriptions.feedId = feeds.id)
            `;
        inConnection!(conn => conn.execParams(p));
    }
}

class ScrubReadArticles : Task
{
    void run()
    {
        QueryParams p;
        p.sqlCommand = `
            DELETE FROM read
            WHERE NOT EXISTS
                (SELECT * FROM articles WHERE id = read.articleId)
            `;
        inConnection!(conn => conn.execParams(p));
    }
}

class ReadFeed : FeedTask
{
    void run(ref Feed feed)
    {
        auto oldArticles = query!Article(`
            SELECT * FROM articles
            WHERE feedId = $1
            ORDER BY publishDate DESC
            LIMIT 10`, feed.id.toString);
        auto newArticles = feed.fetchArticles;
        foreach (article; newArticles)
        {
            import std.algorithm.searching : any;
            if (oldArticles.any!((Article x) => x.isProbablySameAs(article)))
            {
                break;
            }
            insert(article);
        }
    }
}

class ScrubOldArticles : FeedTask
{
    void run(ref Feed feed)
    {
        auto count = query!ulong(
                `SELECT COUNT(*) FROM articles WHERE feedId = $1`, feed.id.toString)[0];
        if (count > MAX_SAVED_ARTICLES)
        {
            QueryParams p;
            p.sqlCommand = `DELETE FROM articles WHERE feedId = $1 AND id NOT IN
                (SELECT id FROM articles WHERE feedId = $1 ORDER BY publishDate DESC limit $2)`;
            p.args = [
                toValue(feed.id.toString),
                toValue(MAX_SAVED_ARTICLES)
            ];
            inConnection!(conn => conn.execParams(p));
        }
    }
}