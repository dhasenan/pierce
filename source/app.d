module pierce.app;

import etc.linux.memoryerror;
import std.experimental.logger;
import std.stdio;
import vibe.d;

import pierce.config : build, config, Config;
import pierce.controllers.core;
import pierce.controllers.feeds;
import pierce.controllers.login;
import pierce.controllers.users;
import pierce.db.migrate;
import pierce.log;
import pierce.tasks;

__gshared MultiLogger log;
shared static this()
{
    registerMemoryErrorHandler();
    log = new MultiLogger;
    log.insertLogger("console", new std.experimental.logger.FileLogger(stderr));
    sharedLog = log;
}

void main(string[] args)
{
    version (unittest) return;
    import std.getopt;

    string cmd = "run";
    string configFile = "config.json";
    ushort port = 9881;

    auto helpInfo = getopt(args,
            "command|cmd", "command [run,dump,migrate,stress]", &cmd,
            "config|c", "path to config file", &configFile);
    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter(
                "Pierce RSS reader!\n" ~ build.toString,
                helpInfo.options);
        return;
    }

    if (existsFile(configFile))
    {
        config = new Config(configFile);
    }
    else
    {
        config = new Config();
    }

    infof("logging to %s", config.logPathFormat);
    log.insertLogger("file", new VibeRollingFileLogger(
                config.logPathFormat,
                std.experimental.logger.LogLevel.all));
    infof("logging initialized");

    dbMigrate();

    if (cmd == "dump")
    {
        import pierce.mongo;
        dumpMongo();
        return;
    }
    if (cmd == "migrate")
    {
        import pierce.mongo;
        readMongo();
        return;
    }

    infof("starting pierce %s", build);

    // Set up background processes.
    runTask(() => pierce.tasks.tasks.run());

    // Set up http server.
    auto settings = new HTTPServerSettings;
    settings.port = 9881;
    auto router = new URLRouter;
    auto fsettings = new HTTPFileServerSettings;
    fsettings.serverPathPrefix = "/static";
    router.get("/static/*", serveStaticFiles("static/", fsettings));
    router.get("/", serveStaticFile("static/index.html"));
    router.get("/favicon.ico", serveStaticFile("static/favicon.ico"));
    router.registerWebInterface(new Authed!(FeedsControllerImpl, "feeds"));
    router.registerWebInterface(new Authed!(UsersControllerImpl, "users"));
    router.registerWebInterface(new LoginController);
    listenHTTP(settings, router);

    runApplication((string[] args) {});
}

