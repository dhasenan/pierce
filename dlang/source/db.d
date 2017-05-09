module pierce.db;

import vibe.db.postgresql;

T parse(T)(Row row)
{
    import std.traits;
    import std.datetime;
    import std.uuid;

    T val;
    static if (is(T == class))
    {
        val = new T();
    }

    foreach (m; __traits(derivedMembers, T))
    {
        if (m !in row)
        {
            continue;
        }
        auto val = row[m].as!string;

        alias FT = typeof(__traits(getMember, T, m));
        static if (isFunction!FT)
        {
            continue;
        }
        else static if (is(FT == UUID))
        {
            __traits(getMember, T, m) = val.parseUUID;
        }
        else static if (is(FT == SysTime))
        {
            __traits(getMember, T, m) = SysTime.fromSimpleString(val);
        }
        else static if (is(FT == string))
        {
            __traits(getMember, T, m) = val;
        }
        else static if (is(FT == Duration))
        {
            __traits(getMember, T, m) = dur!"seconds"(val.to!int);
        }
        else static if (is(FT == int))
        {
            __traits(getMember, T, m) = val.to!int;
        }
        else
        {
            static assert(false, "can't deserialize " ~ FT.stringof ~ " from DB");
        }
    }
}

QueryParams toParams(T)(T val, bool trailingId)
{
    Value[__traits(derivedMembers, T).length + 1] v;
    int i = 0;
    foreach (m; __traits(derivedMembers, T))
    {
        alias FT = typeof(__traits(getMember, T, m));
        string str;
        static if (isFunction!FT)
        {
            continue;
        }
        else static if (is(FT == SysTime))
        {
            str = __traits(getMember, T, m).toISOString(val);
        }
        else static if (is(FT == Duration))
        {
            str = __traits(getMember, T, m).total!("seconds").to!string;
        }
        else
        {
            str = __traits(getMember, T, m).to!string;
        }
        v[i] = toValue(str, ValueFormat.TEXT);
        i++;
    }
    if (trailingId)
    {
        v[i] = toValue(T.id.to!string, ValueFormat.TEXT);
        i++;
    }
    QueryParams p;
    p.args = v[0..i];
    return p;
}

string updateText(T)()
{
    string cmd = `UPDATE "` ~ T.stringof ~ `" SET `;
    int i = 0;
    foreach (m; __traits(derivedMembers, T))
    {
        alias FT = typeof(__traits(getMember, T, m));
        static if (isFunction!FT)
        {
            continue;
        }
        i++;
        if (i > 1)
        {
            cmd ~= `, `;
        }
        cmd ~= m;
        cmd ~= ` = $`;
        cmd ~= i.to!string;
    }
    v[i] = toValue(T.id.to!string, ValueFormat.TEXT);
    i++;
    cmd ~= ` WHERE id = $`;
    cmd ~= i.to!string;
    return cmd;
}

string insertText(T)()
{
    string cmd = `INSERT INTO "` ~ T.stringof ~ ` (`;
    int i = 0;
    foreach (m; __traits(derivedMembers, T))
    {
        alias FT = typeof(__traits(getMember, T, m));
        static if (isFunction!FT)
        {
            continue;
        }
        i++;
        if (i > 1)
        {
            cmd ~= `, `;
        }
        cmd ~= m;
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
    enum cmd = `SELECT * FROM "` ~ T.stringof.toLower ~ `" WHERE id = $1`;
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
    params.argsFromArray = params;
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
