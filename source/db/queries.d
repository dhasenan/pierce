module pierce.db.queries;

import vibe.core.log;
import dpq2;

import std.conv;
import std.datetime;
import std.string;
import std.traits;
import std.typecons;
import std.uuid;

import pierce.datetimeformat;
import pierce.db.core;
import pierce.domain;

/**
  * Save a new user.
  *
  * Should probably just use insert(user).
  */
void saveUser(User user)
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
        p.sqlCommand = `
            INSERT INTO users (id, email, sha, pbkdf2, checkInterval)
            VALUES (uuid($1), $2, $3, $4, $5)`;
        return conn.execParams(p);
    })();
}

void deleteSub(User user, string id)
{
    QueryParams p;
    p.sqlCommand = "DELETE FROM subscriptions WHERE userId = $1 AND feedId = $2";
    p.args = [
        toValue(user.id.toString()),
        toValue(id)
    ];
    inConnection!((conn) => conn.execParams(p));
}

void markUnread(User user, string feedId, string articleId)
{
    QueryParams p;
    p.sqlCommand = "DELETE FROM read WHERE userId = $1 AND feedId = $2 AND articleId = $3";
    p.args = [
        toValue(user.id.toString()),
        toValue(feedId),
        toValue(articleId),
    ];
    inConnection!(conn => conn.execParams(p));
}

void markRead(User user, string feedId, string articleId)
{
    QueryParams p;
    p.sqlCommand = `INSERT INTO read (userId, feedId, articleId) VALUES ($1, $2, $3)
        ON CONFLICT DO NOTHING`;
    p.args = [toValue(user.id.toString), toValue(feedId), toValue(articleId)];
    inConnection!(conn => conn.execParams(p));
}

void markOlderRead(User user, string feedId, string articleId)
{
    QueryParams p;
    p.sqlCommand = `
        INSERT INTO read (userId, feedId, articleId)
        SELECT $1, $2, id
        FROM articles
        WHERE feedId = $2
        AND publishDate < (SELECT publishDate FROM articles WHERE id = $3)
        AND NOT EXISTS (
                SELECT * FROM read
                WHERE articles.id = read.articleId
                AND read.userId = $1)
        `;
    p.args = [toValue(user.id.toString), toValue(feedId), toValue(articleId)];
    inConnection!(conn => conn.execParams(p));
}

