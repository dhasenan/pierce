module pierce.app;

import etc.linux.memoryerror;

import vibe.d;

import pierce.controllers;
import pierce.tasks;
import pierce.vibeutil;

shared static this()
{
    registerMemoryErrorHandler();
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

