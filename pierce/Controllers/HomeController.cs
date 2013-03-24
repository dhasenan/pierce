using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;
using pierce;

namespace Controllers
{
    public class HomeController : BaseController
    {
        public ActionResult Index()
        {
            return View();
        }

        public ActionResult FeedData()
        {
            ReadFeeds r = new ReadFeeds();
            var f = new Feed { Uri = new Uri("http://gdata.youtube.com/feeds/base/users/yogscast2/uploads?alt=rss&v=2") };
            r.Read(f);
            return this.Json(f.Articles);
        }
    }
}

