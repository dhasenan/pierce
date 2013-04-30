using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;
using MongoDB.Bson;
using MongoDB.Driver.Builders;
using System.Web.Security;
using log4net;

namespace pierce
{
    public class BaseController : Controller
    {
        protected ILog log;
        protected Mongo db;

        public BaseController(Mongo db)
        {
            this.db = db;
            log = LogManager.GetLogger(this.GetType());
        }

        protected new ActionResult Json(object o)
        {
            return Json(o, JsonRequestBehavior.AllowGet);
        }

        protected User GetUser()
        {
            if (!User.Identity.IsAuthenticated) return null;
            try
            {
                var id = new ObjectId(User.Identity.Name);
                return db.Users.Find(Query.EQ("_id", id)).FirstOrDefault();
            }
            catch (Exception ex)
            {
                log.Info(ex);
                return null;
            }
        }
    }
}

