using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Web;
using System.Web.Mvc;
using System.Web.Routing;
using MongoDB.Driver;
using log4net;

namespace pierce
{
    public class Pierce : System.Web.HttpApplication
    {
        public static void RegisterRoutes(RouteCollection routes)
        {
            routes.IgnoreRoute("{resource}.axd/{*pathInfo}");
            routes.Ignore("favicon.ico");
            routes.MapRoute(
                "Default",
                "{controller}/{action}",
                new { controller = "Home", action = "Index" }
            );

        }

        public override void Init()
        {
            base.Init();
            this.BeginRequest += (sender, e) => {
                Context.Response.AppendHeader("Access-Control-Allow-Headers", "Content-Type,Origin");
                Context.Response.AppendHeader("Access-Control-Allow-Origin", "*");
            };
        }

        public static MongoDatabase Cluster;

        public static MongoCollection<User> Users { get { return Cluster.GetCollection<User>("users"); } }

        public static MongoCollection<Feed> Feeds { get { return Cluster.GetCollection<Feed>("feeds"); } }

        private static void OpenDatabase()
        {
            var client = new MongoClient("mongodb://localhost/pierce");
            var server = client.GetServer();
            server.Connect();
            Cluster = server.GetDatabase("pierce");
        }

        private static void StartPeriodicTasks()
        {
            new Thread(() => 
            {
                while (true)
                {
                    try
                    {
                        new ReadFeeds().Execute();
                    }
                    catch (Exception ex)
                    {
                        logger.Error("while updating feeds", ex);
                    }
                    Thread.Sleep(TimeSpan.FromSeconds(60));
                }
            }
            ).Start();
        }

        protected void Application_Start()
        {
            SetupLogging();
            AreaRegistration.RegisterAllAreas();
            RegisterRoutes(RouteTable.Routes);
            OpenDatabase();
            StartPeriodicTasks();
            logger.Error("application started");
        }

        private static ILog logger = LogManager.GetLogger("pierce");

        protected void Application_Error(object sender, EventArgs args)
        {
            logger.Error("Unhandled exception", Server.GetLastError());
        }

        private void SetupLogging()
        {
            log4net.Config.XmlConfigurator.ConfigureAndWatch(new System.IO.FileInfo("log4net.config"));
            /*
            log4net.Repository.Hierarchy.Hierarchy repository = (log4net.Repository.Hierarchy.Hierarchy) LogManager.GetRepository();
            if (Environment.OSVersion.Platform == PlatformID.Unix || Environment.OSVersion.Platform == PlatformID.Unix)
            {
                repository.Root.AddAppender(new log4net.Appender.AnsiColorTerminalAppender());
            }
            else
            {
                repository.Root.AddAppender(new log4net.Appender.ColoredConsoleAppender());
            }
            */
        }
    }
}
