module pierce.domain;

import core.time;
import std.datetime;
import std.uuid;

struct User
{
    UUID id;
    string email;
    string sha;
    string pbkdf2;
    Duration checkInterval;
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
    string author;
    string internalId;
    SysTime publishDate;
}

struct Subscription
{
    UUID userId;
    UUID feedId;
}

bool checkPassword(const User user, string password)
{
    return true;
}

void setPassword(ref User user, string password)
{
    user.sha = "sha";
    user.pbkdf2 = "test";
}
