module pierce.db.core;

import core.time;
import dpq2;
import dpq2.conv.time;

import pierce.datetimeformat;
import pierce.domain;
import pierce.log;

import std.conv;
import std.datetime;
import std.experimental.logger;
import std.string;
import std.traits;
import std.typecons;
import std.uuid;

/** Attribute to mark a field as transient (don't save it). */
struct Transient {}

enum Conflict
{
    noop,
    update,
    error
}

__gshared MultiLogger dblog;
shared static this()
{
    // Be absolutely certain we don't have the wrong init order
    if (VibeRollingFileLogger.classinfo.name == "")
    {
        tracef("");
    }
    // So I can manipulate its log level separately
    dblog = new MultiLogger(LogLevel.trace);
    dblog.insertLogger("parent", sharedLog);
}


/**
  * Update a DB row.
  */
void update(T)(T val)
{
    static immutable string cmd = updateText!T();
    dblog.trace(cmd);
    dblog.tracef("param: %s", val);
    auto params = val.toParams(true);
    params.sqlCommand = cmd;
    inConnection!(conn => conn.execParams(params));
}

/**
  * Insert a new DB row.
  */
void insert(T, Conflict onConflict = Conflict.error)(ref T val)
{
    static if (is (typeof(val.id) == UUID))
    {
        val.id = randomUUID();
    }
    static immutable string cmd = insertText!(T, onConflict);
    dblog.trace(cmd);
    dblog.tracef("param: %s", val);
    auto params = val.toParams(false);
    params.sqlCommand = cmd;
    inConnection!(conn => conn.execParams(params));
}

void insertConn(T)(ref scope Connection conn, ref T val)
{
    if (conn is null)
    {
        errorf("querying with existing connection: connection is null");
    }
    else if (conn.status != 0)
    {
        errorf("unexpected status from connection: %s", conn.status);
    }
    if (conn is null)
    {
        insert(val);
    }
    static if (is (typeof(val.id) == UUID))
    {
        val.id = randomUUID();
    }
    static immutable string cmd = insertText!(T, Conflict.error);
    auto params = val.toParams(false);
    params.sqlCommand = cmd;
    conn.execParams(params);
}

auto queryConn(T = void)(ref scope Connection conn, string cmd, string[] args...)
{
    if (conn is null)
    {
        errorf("querying with existing connection: connection is null");
    }
    else if (conn.status != 0)
    {
        errorf("unexpected status from connection: %s", conn.status);
    }
    dblog.tracef("query: [%s] args: %s", cmd, args);
    QueryParams params;
    params.argsFromArray = args;
    params.sqlCommand = cmd;
    auto result = conn.execParams(params);
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
    dblog.tracef("query: [%s] args: %s", cmd, args);
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
        else static if (is(FT == bool))
        {
            __traits(getMember, val, m) = cell.as!bool;
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
        static if (!isFunction!FT && !hasUDA!(__traits(getMember, T, m), Transient))
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

string insertText(T, Conflict onConflict = Conflict.error)()
{
    string cmd = `INSERT INTO ` ~ T.stringof.toLower ~ `s (`;
    int i = 0;
    string values = ``;
    foreach (m; __traits(derivedMembers, T))
    {
        alias FT = typeof(__traits(getMember, T, m));
        static if (!isFunction!FT && !hasUDA!(__traits(getMember, T, m), Transient))
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
    cmd ~= values ~ `)`;
    final switch (onConflict)
    {
        case Conflict.update:
            cmd ~= ` ON CONFLICT DO UPDATE`;
            break;
        case Conflict.noop:
            cmd ~= ` ON CONFLICT DO NOTHING`;
            break;
        case Conflict.error:
            // default behavior
            break;
    }
    return cmd;
}

// TODO connection pooling
auto inConnection(alias fn)()
{
    import vibe.core.core : runWorkerTask;
    import vibe.core.sync : createManualEvent;

    auto evt = createManualEvent;
    static string connectionString;
    if (connectionString.length == 0)
    {
        import std.array : Appender;
        import std.string : strip;
        import pierce.config : config;

        Appender!string builder;
        auto url = config.db;
        if (url.user)
        {
            builder ~= " user=";
            builder ~= url.user;
        }
        if (url.pass)
        {
            builder ~= " password=";
            builder ~= url.pass;
        }
        if (url.port != 0)
        {
            builder ~= " port=";
            builder ~= url.port.to!string;
        }
        if (url.path.length > 1)
        {
            // url is '/' followed by a db name
            builder ~= " dbname=";
            builder ~= url.path[1..$];
        }
        connectionString = builder.data.strip;
    }

    Throwable err = null;
    void* res;
    void delegate () @trusted dg = () @trusted {
        scope conn = new Connection(connectionString);
        scope (exit) evt.emit;
        try
        {
            res = cast(void*)fn(conn);
        }
        catch (Throwable e)
        {
            err = e;
            res = null;
        }
    };
    // This is honestly disgusting.
    // However, it doesn't result in any more data races than we'd otherwise have.
    runWorkerTask(&fakeShared, cast(ulong)cast(void*)&dg);
    evt.wait;

    if (res is null && err !is null)
    {
        throw err;
    }
    return cast(immutable(Answer))res;
}

void fakeShared(ulong p)
{
    auto dg = *cast(void delegate()*)cast(void*)p;
    dg();
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


void stress()
{
    import vibe.core.core : sleep;
    import core.time;
    import std.stdio : writefln;

    ulong queries = 0;
    while (true)
    {
        query!User("SELECT * FROM users");
        queries++;
        if (queries % 500 == 0)
        {
            writefln("finished %s queries", queries);
        }
        sleep(10.msecs);
    }
}
