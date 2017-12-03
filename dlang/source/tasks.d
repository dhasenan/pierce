module pierce.tasks;

import dpq2;
import std.datetime;
import std.experimental.logger;
import vibe.core.core : sleep;

import pierce.datetimeformat;
import pierce.db;
import pierce.domain;
import pierce.feeds;

enum MAX_SAVED_ARTICLES = 1000;

__gshared MultiLogger tasklog;
__gshared TaskRunner tasks;
shared static this()
{
    // So I can manipulate its log level separately
    tasklog = new MultiLogger(LogLevel.info);
    tasklog.insertLogger("parent", sharedLog);
    tasks = new TaskRunner;
}

class TaskRunner
{
    Task[] tasks;
    FeedTask[] feedTasks;

    this()
    {
        tasks = buildTasks();
        feedTasks = buildFeedTasks();
    }

    void run()
    {
        while (true)
        {
            runStandardTasks();
            runFeedTasks();
            sleep(60.seconds);
        }
    }

    void runStandardTasks()
    {
        tasklog.infof("running periodic tasks");
        foreach (task; tasks)
        {
            try
            {
                tasklog.infof("running task %s", task);
                task.run();
            }
            catch (Throwable t)
            {
                tasklog.errorf("in task %s: %s", task, t);
            }
        }
    }

    void runFeedTasks()
    {
        import std.datetime;
        import pierce.datetimeformat;
        auto feeds = query!Feed(`
            SELECT * FROM feeds
            WHERE nextRead IS NULL OR nextRead < $1::timestamp
            ORDER BY lastRead
            LIMIT 100`, Clock.currTime(UTC()).format(ISO8601FORMAT));
        tasklog.infof("scanning %s feeds", feeds.length);
        foreach (feed; feeds)
        {
            runTasksOnFeed(feed);
        }
    }

    void runTasksOnFeed(Feed feed)
    {
        foreach (feedTask; feedTasks)
        {
            try
            {
                tasklog.infof("running task %s", feedTask);
                feedTask.run(feed);
            }
            catch (Throwable t)
            {
                tasklog.errorf("in feed task %s: %s", feedTask, t);
            }

        }
        update(feed);
        // put this in the main log so it's sure to be visible
        infof("feed %s next scheduled check: %s", feed.url, feed.nextRead.format(ISO8601FORMAT));
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
        new ScheduleNextCheck(),
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
        // This has a race condition where everyone unsubs from feed S, someone starts subscribing,
        // then this runs. dpq2 doesn't seem to support transactions...
        p.sqlCommand = `
            DELETE FROM feeds
            WHERE lastRead IS NOT NULL
            AND created < now() - '30 minutes'::interval
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

class ScheduleNextCheck : FeedTask
{
    private Duration minCheckInterval = 1.hours;

    void run(ref Feed feed)
    {
        Duration interval = feed.checkInterval;
        if (interval < minCheckInterval)
        {
            interval = minCheckInterval;
        }
        auto now = Clock.currTime(UTC());
        feed.nextRead = now + interval;
    }
}
