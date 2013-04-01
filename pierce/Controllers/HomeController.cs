using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;

namespace pierce
{
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            return Redirect("/Content/index.html");
        }
    }
}

