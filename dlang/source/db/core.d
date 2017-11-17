module pierce.db.core;

import core.time;
import dpq2;
import dpq2.conv.time;

import pierce.datetimeformat;
import pierce.domain;

import std.conv;
import std.datetime;
import std.experimental.logger;
import std.string;
import std.traits;
import std.typecons;
import std.uuid;

__gshared MultiLogger dblog;
shared static this()
{
    // So I can manipulate its log level separately
    dblog = new MultiLogger(LogLevel.warning);
    dblog.insertLogger("parent", sharedLog);
}


/**
  * Update a DB row.
  */
void update(T)(T val)
{
    enum cmd = updateText!T();
    dblog.infof("update cmd: %s", cmd);
    auto params = val.toParams(true);
    params.sqlCommand = cmd;
    inConnection!(conn => conn.execParams(params));
}

/**
  * Insert a new DB row.
  */
void insert(T)(ref T val)
{
    static if (is (typeof(val.id) == UUID))
    {
        val.id = randomUUID();
    }
    static immutable string cmd = insertText!T();
    auto params = val.toParams(false);
    import std.algorithm : joiner, map;
    params.sqlCommand = cmd;
    inConnection!(conn => conn.execParams(params));
}

/**
  * Update the value if it's already in the database, otherwise insert it.
  *
  * This relies on newly created items not having IDs. This might not work well for stuff that's got
  * complex creation steps; in that case, you need to manually call insert.
  */
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

/**
  * Delete something from the database.
  */
void dbdelete(T)(T val)
{
    dbdelete!T(val.id);
}

/**
  * Delete something from the database.
  */
void dbdelete(T)(UUID id)
{
    query!void("DELETE FROM " ~ T.stringof ~ "s WHERE id = ?", id.to!string);
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

/**
  * Execute a query, parsing the results automatically.
  */
auto query(T = void)(string cmd, string[] args...)
{
    QueryParams params;
    params.argsFromArray = args;
    params.sqlCommand = cmd;
    auto result = inConnection!(conn => conn.execParams(params));
    static if (!is(T == void))
    {
        auto vals = new T[result.length];
        foreach (i, ref v; vals)
        {
            v = parse!T(result[i]);
        }
        return vals;
    }
}

// Parse a DB row out into a class or struct instance.
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

    foreach (mm; FieldNameTuple!T)
    {
        const m = mm;
        alias FT = typeof(__traits(getMember, T, m));

        bool found = false;
        string normalName = m;
        for (int i = 0; i < row.length; i++)
        {
            import std.uni : sicmp;

            auto name = row.columnName(i);
            if (sicmp(name, m) == 0)
            {
                normalName = name;
                found = true;
                break;
            }
        }
        if (!found)
        {
            continue;
        }

        auto cell = row[normalName];
        if (cell.isNull)
        {
            // should have default value here
            continue;
        }

        static if (isFunction!FT)
        {
            continue;
        }
        else static if (is(FT == UUID))
        {
            auto s = cell.as!string;
            __traits(getMember, val, m) = s.parseUUID;
        }
        else static if (is(FT == SysTime))
        {
            auto sansTZ = cell.as!TimeStampWithoutTZ;
            auto st = SysTime(sansTZ.dateTime, sansTZ.fracSec.hnsecs.hnsecs, UTC());
            __traits(getMember, val, m) = st;
        }
        else static if (is(FT == string))
        {
            __traits(getMember, val, m) = cell.as!string;
        }
        else static if (is(FT == Duration))
        {
            __traits(getMember, val, m) = dur!"seconds"(cell.as!int);
        }
        else static if (is(FT == int))
        {
            __traits(getMember, val, m) = cell.as!int;
        }
        else
        {
            static assert(false, "can't deserialize " ~ FT.stringof ~ " from DB");
        }
    }
    return val;
}

// Parse a DB row out into a struct.
T parse(T)(immutable Row row) if (!is(T == class) && !is(T == struct))
{
    return row[0].as!T;
}

// Convert a thingy into a query parameter set.
QueryParams toParams(T)(T val, bool trailingId)
{
    // I suspect I have too much space here.
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
                if (fieldVal == SysTime.init)
                {
                    // TODO send default / null value?
                }
                else
                {
                    auto fs = fieldVal.format(ISO8601FORMAT);
                    v[i] = toValue(fs);
                    dblog.infof("field %s value %s", i, fs);
                }
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
            else static if (isNumeric!FT)
            {
                v[i] = toValue(fieldVal);
            }
            else
            {
                v[i] = toValue(std.conv.to!string(fieldVal));
            }
            v[i].data();
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
    p.args = v[0..i].dup;
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
            else static if (is(FT == SysTime))
            {
                cmd ~= '$';
                cmd ~= i.to!string;
                cmd ~= `::timestamp without time zone`;
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
            else static if (is(FT == SysTime))
            {
                values ~= `$`;
                values ~= i.to!string;
                values ~= `::timestamp without time zone`;
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
