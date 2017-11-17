module pierce.db.migrate;

import dpq2;
import dpq2.exception;
import pierce.db.core;
import std.datetime;
import std.experimental.logger;
import std.string;
import vibe.core.log;

void dbMigrate()
{
    import std.algorithm.setops : setDifference;
    import std.algorithm.sorting : sort;
    import std.array : array;
    infof("running database migrations");

    auto base = import("base.sql");

    Migration[] migrations =
    [
    ];
    sort(migrations);
    migrations = [read!"base.sql"] ~ migrations;
    Migration[] finishedMigrations;
    try
    {
       finishedMigrations = query!Migration("select * from migrations");
    }
    catch (Exception e)
    {
        // Probably the table doesn't yet exist.
    }
    sort(finishedMigrations);

    // Might want to check if we're applying out of order...
    auto toApply = setDifference(migrations, finishedMigrations).array;
    // Just in case.
    sort(toApply);

    infof("%s migrations already run, %s defined, %s remaining",
            finishedMigrations.length,
            migrations.length,
            toApply.length);

    foreach (migration; toApply)
    {
        infof("applying migration %s", migration.name);
        apply(migration.name, migration.script);
        infof("migration applied");
    }
}

class MigrationException : Exception
{
    this(string message, Throwable next, string file = __FILE__, ulong line = __LINE__)
    {
        super(message, file, line, next);
    }
}

struct Migration
{
    string name;
    string script;
    SysTime applied;

    int opCmp(Migration other)
    {
        import std.uni : sicmp;
        return sicmp(name, other.name);
    }
}

private:

Migration read(string name)()
{
    return Migration(name, import(name), Clock.currTime(UTC()));
}

void applyPart(Connection conn, string name, string part)
{
    QueryParams p;
    p.sqlCommand = part;
    try
    {
        conn.execParams(p);
    }
    catch (Dpq2Exception e)
    {
        errorf("error applying migration %s!\nscript was: %s\nerror: %s",
                name, part, e);
        throw new MigrationException(
                "while applying " ~ name ~ ", specifically:\n" ~ part, e);
    }

}

void apply(string name, string script, bool record = true)
{
    inConnection!((conn)
    {
        foreach (part; script.split(';'))
        {
            import std.string : strip;
            if (part.strip.length == 0) continue;
            applyPart(conn, name, part);
        }
        if (record)
        {
            auto m = Migration(name, script, Clock.currTime(UTC()));
            insert(m);
        }
        return cast(void*)null;
    });
}