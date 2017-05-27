module pierce.db;

import vibe.db.postgresql;
import std.conv;
import std.string;
import std.traits;
import std.datetime;

T parse(T)(immutable Row row)
{
    import std.traits;
    import std.datetime;
    import std.uuid;

    T val;
    static if (is(T == class))
    {
        val = new T();
    }

    foreach (mm; __traits(derivedMembers, T))
    {
        const m = mm;
        bool found = false;
        for (int i = 0; i < row.length; i++)
        {
            if (row.columnName(i) == m)
            {
                found = true;
                break;
            }
        }
        if (!found) continue;

        auto v = row[m].as!string;

        alias FT = typeof(__traits(getMember, T, m));
        static if (isFunction!FT)
        {
            continue;
        }
        else static if (is(FT == UUID))
        {
            __traits(getMember, val, m) = v.parseUUID;
        }
        else static if (is(FT == SysTime))
        {
            __traits(getMember, val, m) = SysTime.fromSimpleString(v);
        }
        else static if (is(FT == string))
        {
            __traits(getMember, val, m) = v;
        }
        else static if (is(FT == Duration))
        {
            __traits(getMember, val, m) = dur!"seconds"(std.conv.to!int(v));
        }
        else static if (is(FT == int))
        {
            __traits(getMember, val, m) = std.conv.to!int(v);
        }
        else
        {
            static assert(false, "can't deserialize " ~ FT.stringof ~ " from DB");
        }
    }
    return val;
}

QueryParams toParams(T)(T val, bool trailingId)
{
    Value[__traits(derivedMembers, T).length + 1] v;
    int i = 0;
    foreach (m; __traits(derivedMembers, T))
    {
        alias FT = typeof(__traits(getMember, T, m));
        string str;
        static if (!isFunction!FT)
        {
            static if (is(FT == SysTime))
            {
                str = __traits(getMember, val, m).toISOString(val);
            }
            else static if (is(FT == Duration))
            {
                str = __traits(getMember, val, m).total!("seconds").to!string;
            }
            else static if (is(FT == string))
            {
                str = __traits(getMember, val, m);
            }
            else
            {
                str = std.conv.to!string(__traits(getMember, val, m));
            }
            v[i] = toValue(str, ValueFormat.TEXT);
            i++;
        }
    }
    if (trailingId)
    {
        v[i] = toValue(val.id.to!string, ValueFormat.TEXT);
        i++;
    }
    QueryParams p;
    p.args = v[0..i];
    return p;
}

string updateText(T)()
{
    string cmd = `UPDATE ` ~ T.stringof.toLower ~ `s SET `;
    int i = 0;
    foreach (m; __traits(derivedMembers, T))
    {
        alias FT = typeof(__traits(getMember, T, m));
        static if (!isFunction!FT)
        {
            i++;
            if (i > 1)
            {
                cmd ~= `, `;
            }
            cmd ~= m;
            cmd ~= ` = $`;
            cmd ~= i.to!string;
        }
    }
    i++;
    cmd ~= ` WHERE id = $`;
    cmd ~= i.to!string;
    return cmd;
}

string insertText(T)()
{
    string cmd = `INSERT INTO ` ~ T.stringof.toLower ~ `s (`;
    int i = 0;
    foreach (m; __traits(derivedMembers, T))
    {
        alias FT = typeof(__traits(getMember, T, m));
        if (!isFunction!FT)
        {
            i++;
            if (i > 1)
            {
                cmd ~= `, `;
            }
            cmd ~= m;
        }
    }
    cmd ~= `) VALUES (`;
    for (int x = 1; x <= i; x++)
    {
        if (x > 1)
        {
            cmd ~= `, `;
        }
        cmd ~= `$`;
        cmd ~= x.to!string;
    }
    cmd ~= `)`;
    return cmd;
}

void update(T)(T val)
{
    enum cmd = updateText!T();
    auto params = val.toParams(true);
    params.sqlCommand = cmd;
    inConnection!(conn => conn.execParams(params));
}

void insert(T)(T val)
{
    enum cmd = insertText!T();
    auto params = val.toParams(false);
    params.sqlCommand = cmd;
    inConnection!(conn => conn.execParams(params));
}

Nullable!T fetch(T)(UUID id)
{
    enum cmd = `SELECT * FROM ` ~ T.stringof.toLower ~ `s WHERE id = $1`;
    QueryParams params;
    params.argsFromArray = [id.toString];
    params.sqlCommand = cmd;
    auto result = inConnection!(conn => conn.execParams(params));
    if (result.length > 0)
    {
        return parse!T(result[0]);
    }
    return Nullable!T.init;
}

T[] query(T)(string cmd, string[] args)
{
    QueryParams params;
    params.argsFromArray = args;
    params.sqlCommand = cmd;
    auto result = inConnection!(conn => conn.execParams(params));
    auto vals = new T[result.length];
    foreach (i, ref v; vals)
    {
        v = parse!T(result[i]);
    }
    return vals;
}

auto inConnection(alias fn)()
{
    auto conn = pg.lockConnection;
    scope(exit) delete conn;
    return fn(conn);
}

shared PostgresClient pg;
shared static this()
{
    pg = new shared PostgresClient("dbname=pierce user=pierce", 4);
}


/*
   So, a normal query will look like:
   SELECT feed.* FROM feed
       INNER JOIN subscription ON feed.id = subscription.feedId
       WHERE subscription.userId = $1;
   SELECT * FROM article WHERE feedId = $1 ORDER BY publishDate DESC LIMIT 100;
   SELECT * FROM read WHERE feedId = $1 AND userId = $2 ORDER BY publishDate DESC LIMIT 100;
   */

/*
   Find all unread articles for a user:
    SELECT articles.* FROM articles
        INNER JOIN subscriptions ON subscriptions.feedId = articles.feedId
        WHERE subscriptions.userId = :userId AND NOT EXISTS (
            SELECT * FROM read WHERE userId = :userId AND articleId = :articles.id
        )

   That's...not *awesome*, but not the end of the world, and it's probably better than what I
   currently do.
   */
