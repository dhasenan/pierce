module pierce.config;

import url;
import vibe.data.json : parseJson, Json;
import vibe.core.file : readFileUTF8;

__gshared Config config;

class Config
{
    URL db = "postgresql://localhost:5432/pierce".parseURL;
    URL mongo = "mongodb://localhost:27017/pierce".parseURL;
    bool allowRegistrations = true;
    ushort port = 9881;
    string logPathFormat = "logs/pierce-%y-%m-%d.%i.log";

    this(Json js)
    {
        if ("db" in js)
        {
            db = js["db"].get!string.parseURL;
        }
        if ("mongo" in js)
        {
            mongo = js["mongo"].get!string.parseURL;
        }
        if ("allowRegistrations" in js)
        {
            allowRegistrations = js["allowRegistrations"].get!bool;
        }
        if ("port" in js)
        {
            port = js["port"].get!ushort;
        }
        if ("log" in js)
        {
            logPathFormat = js["log"].get!string;
        }
    }

    this(string filename)
    {
        auto data = readFileUTF8(filename);
        this(data.parseJson);
    }

    this()
    {
    }
}

immutable class BuildInfo
{
    string branch, commit, tag, date;

    this()
    {
        import std.string : split;
        string[] versionInfo = import("version.txt").split('\n');
        branch = versionInfo[0];
        commit = versionInfo[1];
        tag = versionInfo[2];
        date = versionInfo[3];
    }

    string toString() inout
    {
        import std.format : format;
        return format(
                "build on %s from revision %s, branch %s, based on version %s",
                date,
                tag,
                branch,
                commit[0..8]);
    }
}

immutable BuildInfo build;
shared static this()
{
    build = new immutable BuildInfo();
}

private T get(T)(Json json, string key, T defaultValue)
{
    if (key in json)
    {
        return json[key].get!T;
    }
    return defaultValue;
}
