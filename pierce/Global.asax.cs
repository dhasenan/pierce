using System;
using System.Web.WebPages.Scope;
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
using System.Net;
using System.Security.Cryptography.X509Certificates;
using System.Net.Security;

namespace pierce
{
    // We don't use TempData, and SessionStateInProcHandler dies constantly in Mono, so disable it (and SessionState).
    public class SessionlessTempDataProvider : ITempDataProvider
    {
        public IDictionary<string, object> LoadTempData(ControllerContext controllerContext)
        {
            return new Dictionary<string, object>();
        }

        public void SaveTempData(ControllerContext controllerContext, IDictionary<string, object> values)
        {
        }
    }

    // This class taken pretty much directly from the Windsor docs.
    public class WindsorControllerFactory : DefaultControllerFactory
    {
        private readonly IKernel kernel;
        private readonly ITempDataProvider dataProvider;
 
        public WindsorControllerFactory(IKernel kernel)
        {
            this.kernel = kernel;
            dataProvider = new SessionlessTempDataProvider();
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
            var controller = (Controller)kernel.Resolve(controllerType);
            controller.TempDataProvider = dataProvider;
            return controller;
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
        protected void Application_BeginRequest()
        {
            var moduleType = typeof(AspNetRequestScopeStorageProvider).Assembly.GetType("System.Web.WebPages.WebPageHttpModule");
            var property = moduleType.GetProperty("AppStartExecuteCompleted", BindingFlags.NonPublic | BindingFlags.Static);
            property.SetValue(null, true, null);
        }

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

        private static void StartPeriodicTasks()
        {
            var thread = new Thread(() => 
            {
                while (true)
                {
                    try
                    {
                        var feedReader = Container.Resolve<FeedMaintenance>();
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

		private static void SetupWindsor()
		{
			Container = new WindsorContainer();
			Container.Kernel.Resolver.AddSubResolver(new LoggerResolver(new MyLoggerFactory()));
			Container.Kernel.Resolver.AddSubResolver(new ArrayResolver(Container.Kernel));
			Container.Register(Classes.FromAssembly(Assembly.GetAssembly(typeof(HomeController))).Pick().Unless(x => typeof(IFeedTask).IsAssignableFrom(x)).WithServiceSelf().LifestyleTransient());
			Container.Register(Classes.FromAssembly(Assembly.GetAssembly(typeof(ChunkShuffler))).BasedOn<IFeedTask>().WithServiceFirstInterface().LifestyleTransient());
			ControllerBuilder.Current.SetControllerFactory(new WindsorControllerFactory(Container.Kernel));
		}

		private static void SetupHttpsPolicy()
		{
			var conf = Container.Resolve<PierceConfig>();
			if (!conf.TrustAllCertificates)
			{
				return;
			}
			ServicePointManager.ServerCertificateValidationCallback = (object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) => {
				if (errors != SslPolicyErrors.None)
				{
					logger.InfoFormat("SSL certificate didn't validate; going ahead anyway. Problem was {0}", errors);
				}
				return true;
			};
		}

        protected void Application_Start()
        {
            SetupLogging();
            try
            {
                logger.Info("setting up windsor");
                SetupWindsor();
                logger.Info("registering areas and routes");
                AreaRegistration.RegisterAllAreas();
                RegisterRoutes(RouteTable.Routes);
				logger.Info("setting up HTTPS policy");
				SetupHttpsPolicy();
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
