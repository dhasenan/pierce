module pierce.domain;

import core.time;
import std.datetime;
import std.uuid;

// TODO structs vs classes?
struct User
{
    UUID id;
    string email;
    ubyte[] sha;
    ubyte[] pbkdf2;
    int checkInterval;
}

struct Feed
{
    UUID id;
    string url;
    string title;
    string iconURL;

    Duration checkInterval;
    SysTime nextRead;
    SysTime lastRead;
    int errors;

}

struct Article
{
    UUID id;
    UUID feedId;
    string url;
    string title;
    string description;
    SysTime publishDate;
}

// TODO do we even need this?
struct Subscription
{
    UUID userId;
    UUID feedId;
}
