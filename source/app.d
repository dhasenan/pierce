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

shared static this()
{
    registerMemoryErrorHandler();
}

int main(string[] args)
{
    version (unittest) return 0;
    import std.getopt;

    string cmd = "run";
    string configFile = "config.json";

    auto helpInfo = getopt(args,
            "command|cmd", "command [run,dump,migrate,stress]", &cmd,
            "config|c", "path to config file", &configFile);
    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter(
                "Pierce RSS reader!\n" ~ build.toString,
                helpInfo.options);
        return 1;
    }

    if (existsFile(configFile))
    {
        config = new Config(configFile);
    }
    else
    {
        config = new Config();
    }

    dbMigrate();

    switch (cmd)
    {
        case "dump":
            import pierce.mongo;
            dumpMongo();
            return 0 ;
        case "migrate":
            import pierce.mongo;
            readMongo();
            return 0 ;
        case "poll":
            setupLogging(config, "pierce.poll");
            runTask(() => pierce.tasks.tasks.run());
            break;
        case "web":
            setupLogging(config, "pierce.web");
            listen(config);
            break;
        case "fork":
            import std.file : thisExePath;
            import std.process;
            auto poller = spawnProcess(
                    [thisExePath, "--config", configFile, "--command", "poll"],
                    null,
                    std.process.Config.detached);
            auto web = spawnProcess(
                    [thisExePath, "--config", configFile, "--command", "web"],
                    null,
                    std.process.Config.detached);
            break;
        case "run":
            setupLogging(config, "pierce");
            runTask(() => pierce.tasks.tasks.run());
            listen(config);
            break;
        default:
            stderr.writefln("Unrecognized command %s", cmd);
            stderr.writefln("Valid commands: dump, migrate, poll, web, fork, run");
            return 0;
    }
    return runApplication((string[] args) {});
}

void listen(Config config)
{
    infof("starting pierce %s", build);

    // Set up http server.
    auto settings = new HTTPServerSettings;
    settings.port = config.port;
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


void setupLogging(Config cfg, string id)
{
    infof("logging to %s", config.logPathFormat);
    logger.insertLogger("file", new VibeRollingFileLogger(
                config.logPathFormat,
                id,
                std.experimental.logger.LogLevel.all));
    infof("logging initialized");
}
