module pierce.app;

import etc.linux.memoryerror;
import std.experimental.logger;
import std.stdio;
import vibe.d;

import pierce.controllers.core;
import pierce.controllers.feeds;
import pierce.controllers.login;
import pierce.controllers.users;
import pierce.db.migrate;
import pierce.log;
import pierce.tasks;

shared static this()
{
    registerMemoryErrorHandler();
    auto log = new MultiLogger;
    log.insertLogger("console", new std.experimental.logger.FileLogger(stderr));
    log.insertLogger("file", new VibeRollingFileLogger("pierce-%y-%m-%d.%n.log", std.experimental.logger.LogLevel.all));
    sharedLog = log;

    dbMigrate();
    // Set up background processes.
    runTask(() => pierce.tasks.runTasks());

    // Set up http server.
    auto settings = new HTTPServerSettings;
    settings.port = 9881;
    auto router = new URLRouter;
    auto fsettings = new HTTPFileServerSettings;
    fsettings.serverPathPrefix = "/static";
    router.get("/static/*", serveStaticFiles("static/", fsettings));
    router.get("/", serveStaticFile("static/index.html"));
    router.registerWebInterface(new Authed!(FeedsControllerImpl, "feeds"));
    router.registerWebInterface(new Authed!(UsersControllerImpl, "users"));
    router.registerWebInterface(new LoginController);
    listenHTTP(settings, router);
}

