using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;
using MongoDB.Bson;
using MongoDB.Driver.Builders;
using System.Web.Security;

namespace pierce
{
    public class BaseController : Controller
    {
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
                return Pierce.Users.Find(Query.EQ("_id", id)).FirstOrDefault();
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex);
                return null;
            }
        }
    }
}

