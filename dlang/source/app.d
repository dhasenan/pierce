module pierce.app;

import vibe.d;

import pierce.controllers;
import pierce.tasks;
import pierce.vibeutil;

shared static this()
{
    // Set up background processes.
    runTask(() => pierce.tasks.runTasks());

    // Set up http server.
    auto settings = new HTTPServerSettings;
    settings.port = 8080;
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

