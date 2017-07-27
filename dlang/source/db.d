module pierce.db;

import vibe.core.log;
//import vibe.db.postgresql;
import dpq2;

import std.conv;
import std.datetime;
import std.string;
import std.traits;
import std.typecons;
import std.uuid;

import pierce.domain;

T parse(T)(immutable Row row) if (is(T == class) || is(T == struct))
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

        auto cell = row[m];
        if (cell.isNull) continue;
        auto v = cell.as!string;

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

T parse(T)(immutable Row row) if (!is(T == class) && !is(T == struct))
{
    return to!T(row[0].as!string);
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
            auto fieldVal = __traits(getMember, val, m);
            static if (is(FT == SysTime))
            {
                v[i] = toValue(fieldVal.toISOString());
            }
            else static if (is(FT == Duration))
            {
                auto secs =  fieldVal.total!("seconds");
                v[i] = toValue(cast(int)secs);
            }
            else static if (is(FT == string))
            {
                v[i] = toValue(fieldVal);
            }
            else
            {
                v[i] = toValue(std.conv.to!string(fieldVal));
            }
            logInfo("arg %s is %s", i + 1, v[i]);
            i++;
        }
    }
    if (trailingId)
    {
        static if (is (typeof(val.id)))
        {
            v[i] = toValue(val.id.to!string, ValueFormat.TEXT);
            i++;
        }
        else
        {
            throw new Exception(
                    "asked for trailing id for type " ~
                    T.stringof ~ "with no trailing id");
        }
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
            cmd ~= ` = `;
            static if (is(FT == UUID))
            {
                cmd ~= `uuid($` ~ i.to!string ~ `)`;
            }
            else
            {
                cmd ~= '$';
                cmd ~= i.to!string;
            }
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
    string values = ``;
    foreach (m; __traits(derivedMembers, T))
    {
        alias FT = typeof(__traits(getMember, T, m));
        if (!isFunction!FT)
        {
            i++;
            if (i > 1)
            {
                cmd ~= `, `;
                values ~= `, `;
            }
            cmd ~= m;
            static if (is(FT == UUID))
            {
                values ~= `uuid($` ~ i.to!string ~ `)`;
            }
            else
            {
                values ~= `$`;
                values ~= i.to!string;
            }
        }
    }
    cmd ~= `) VALUES (`;
    return cmd ~ values ~ `)`;
}

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
    import std.algorithm : joiner, map;
    params.sqlCommand = cmd;
    inConnection!(conn => conn.execParams(params));
}

void saveOrUpdate(T)(ref T val)
{
    if (val.id == UUID.init)
    {
        val.id = randomUUID;
        insert(val);
    }
    else
    {
        update(val);
    }
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
        return Nullable!T(parse!T(result[0]));
    }
    return Nullable!T.init;
}

T[] query(T)(string cmd, string[] args...)
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

struct Result
{
    Throwable e;
    immutable(Answer) answer;
}
auto inConnection(alias fn)()
{
    import vibe.core.concurrency : async;

    Throwable err = null;
    void* delegate () @trusted dg = () @trusted {
        scope conn = new Connection("dbname=pierce user=dhasenan");
        try
        {
            return cast(void*)fn(conn);
        }
        catch (Throwable e)
        {
            err = e;
            return null;
        }
    };
    auto v = async(dg);
    auto res = v.getResult;
    if (res is null && err !is null)
    {
        throw err;
    }
    return cast(immutable(Answer))res;
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
