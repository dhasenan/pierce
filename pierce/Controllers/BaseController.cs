using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;
using MongoDB.Bson;
using MongoDB.Driver.Builders;

namespace pierce
{
    public class BaseController : Controller
    {
        protected new ActionResult Json(object o)
        {
            return Json(o, JsonRequestBehavior.AllowGet);
        }

        protected ObjectId UserId { get { return new ObjectId(base.User.Identity.Name); } }

        protected new User User
        {
            get
            {
                return Pierce.Users.Find(Query.EQ("_id", UserId)).FirstOrDefault();
            }
        }
    }
}

