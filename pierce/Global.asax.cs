using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Web;
using System.Web.Mvc;
using System.Web.Routing;
using MongoDB.Driver;
using log4net;
using Castle.Windsor;
using Castle.MicroKernel.Registration;
using System.Reflection;
using Castle.MicroKernel;
using Castle.Windsor.Installer;
using Castle.Facilities.Logging;
using Castle.MicroKernel.Context;
using Castle.Core;

namespace pierce
{
    // This class taken pretty much directly from the Windsor docs.
    public class WindsorControllerFactory : DefaultControllerFactory
    {
        private readonly IKernel kernel;
 
        public WindsorControllerFactory(IKernel kernel)
        {
            this.kernel = kernel;
        }
 
        public override void ReleaseController(IController controller)
        {
            kernel.ReleaseComponent(controller);
        }
 
        protected override IController GetControllerInstance(RequestContext requestContext, Type controllerType)
        {
            if (controllerType == null)
            {
                throw new HttpException(404, string.Format("The controller for path '{0}' could not be found.", requestContext.HttpContext.Request.Path));
            }
            return (IController)kernel.Resolve(controllerType);
        }
    }

    public class ArrayResolver : ISubDependencyResolver
    {
        private readonly IKernel kernel;

        public ArrayResolver(IKernel kernel)
        {
            this.kernel = kernel;
        }

        public object Resolve(CreationContext context, ISubDependencyResolver parentResolver, 
                              ComponentModel model,
                              DependencyModel dependency)
        {
            return kernel.ResolveAll(dependency.TargetType.GetElementType(), null);
        }

        public bool CanResolve(CreationContext context, ISubDependencyResolver parentResolver, 
                              ComponentModel model,
                              DependencyModel dependency)
        {
            return dependency.TargetType != null && 
                dependency.TargetType.IsArray && 
                dependency.TargetType.GetElementType().IsInterface;
        }
    }

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

        public static WindsorContainer Container;

        public override void Init()
        {
            base.Init();
            this.BeginRequest += (sender, e) => {
                Context.Response.AppendHeader("Access-Control-Allow-Headers", "Content-Type,Origin");
                Context.Response.AppendHeader("Access-Control-Allow-Origin", "*");
            };
            this.Error += (sender, e) => {
                logger.Error("Unhandled exception", Server.GetLastError());
            };
        }

        public static MongoDatabase Cluster;

        public static MongoCollection<User> Users { get { return Cluster.GetCollection<User>("users"); } }
        
        public static MongoCollection<Feed> Feeds { get { return Cluster.GetCollection<Feed>("feeds"); } }

        public static MongoCollection<Chunk> Chunks { get { return Cluster.GetCollection<Chunk>("chunks"); } }

        private static void OpenDatabase()
        {
            var client = new MongoClient("mongodb://localhost/pierce");
            var server = client.GetServer();
            server.Connect();
            Cluster = server.GetDatabase("pierce");
        }

        private static void StartPeriodicTasks()
        {
            var feedReader = Container.Resolve<FeedMaintenance>();
            var thread = new Thread(() => 
            {
                while (true)
                {
                    try
                    {
                        feedReader.Execute();
                    }
                    catch (Exception ex)
                    {
                        logger.Error("while updating feeds", ex);
                    }
                    Thread.Sleep(TimeSpan.FromSeconds(60));
                }
            }
            );
            thread.Priority = ThreadPriority.Lowest;
            thread.Start();
        }

        protected void Application_Start()
        {
            SetupLogging();
            try
            {
                logger.Info("setting up windsor");
                Container = new WindsorContainer();
                Container.Kernel.Resolver.AddSubResolver(new LoggerResolver(new MyLoggerFactory()));
                Container.Kernel.Resolver.AddSubResolver(new ArrayResolver(Container.Kernel));
                Container.Register(Classes.FromAssembly(Assembly.GetAssembly(typeof(HomeController))).Pick().Unless(x => typeof(IFeedTask).IsAssignableFrom(x)).WithServiceSelf().LifestyleTransient());
                Container.Register(Classes.FromAssembly(Assembly.GetAssembly(typeof(ChunkShuffler))).BasedOn<IFeedTask>().WithServiceFirstInterface());
                ControllerBuilder.Current.SetControllerFactory(new WindsorControllerFactory(Container.Kernel));
                logger.Info("registering areas and routes");
                AreaRegistration.RegisterAllAreas();
                RegisterRoutes(RouteTable.Routes);
                logger.Info("opening database");
                OpenDatabase();
                logger.Info("starting periodic tasks");
                StartPeriodicTasks();
                logger.Info("initialization complete!");
            }
            catch (Exception ex)
            {
                logger.Fatal("unable to set up server!", ex);
            }
        }

        private static ILog logger = LogManager.GetLogger("pierce");

        protected void Application_Error(object sender, EventArgs args)
        {
            logger.Error("Unhandled exception", Server.GetLastError());
        }

        private void SetupLogging()
        {
            log4net.Config.XmlConfigurator.ConfigureAndWatch(new System.IO.FileInfo("log4net.config"));
        }
    }
}
