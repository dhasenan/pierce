using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Web;
using System.Web.Mvc;
using System.Web.Routing;
using MongoDB.Driver;

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

        protected void Application_Start()
        {
            AreaRegistration.RegisterAllAreas();
            RegisterRoutes(RouteTable.Routes);

            var client = new MongoClient("mongodb://localhost/pierce");
            var server = client.GetServer();
            server.Connect();
            Cluster = server.GetDatabase("pierce");

            CreateDatabaseIfNecessary();
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
                        Console.WriteLine("while updating feeds {0}", ex);
                    }
                    Thread.Sleep(TimeSpan.FromSeconds(60));
                }
            }).Start();
        }

        private void CreateDatabaseIfNecessary()
        {
        }
    }
}
