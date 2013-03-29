using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;
using MongoDB.Driver.Builders;
using MongoDB.Bson;

namespace pierce
{
    public class FeedsController : BaseController
    {
        public ActionResult Add(string url)
        {
            var user = GetUser();
            if (user == null)
            {
                Response.StatusCode = 401;
                return Json(new { Error = "Not authenticated" });
            }
            
            var feeds = new AutodetectFeeds().FromHtmlPage(url);
            if (feeds.Count == 1)
            {
                var f = feeds [0];
                var uri = f.Uri.ToString();
                var existing = Pierce.Feeds.Find(Query.EQ("Uri", uri));
                if (existing.Any())
                {
                    f = existing.First();
                }
                else
                {
                    f.Id = ObjectId.GenerateNewId().ToString();
                    Pierce.Feeds.Insert(f);
                }
                user.SubscribeTo(f);
                Pierce.Users.Save(user);
                Pierce.Feeds.Save(f);
                return Json(new { FoundFeeds = true, AddedFeed = f });
            }
            if (feeds.Count > 1)
            {
                return Json(new { FoundFeeds = true, DiscoveredFeeds = feeds });
            }
            return Json(new { FoundFeeds = false });
        }

        public ActionResult Unsubscribe(string id)
        {
            var user = GetUser();
            if (user == null)
            {
                Response.StatusCode = 401;
                return Json(new { Error = "Not authenticated" });
            }
            var sub = user.GetSubscription(id);
            if (sub != null)
            {
                user.Subscriptions.Remove(sub);
            }
            Pierce.Users.Save(user);
            return Json(new object());
        }

        public ActionResult Read(string id)
        {
            var result = Feed.ById(id);
            if (result == null)
            {
                return Json(new { Error = "The requested feed was not found." });
            }
            return Json(result);
        }

        public ActionResult UpdateNow(string id)
        {
            var user = GetUser();
            if (user == null)
            {
                Response.StatusCode = 401;
                return Json(new { Error = "Not authenticated" });
            }
            if (user.GetSubscription(id) == null)
            {
                Response.StatusCode = 404;
                return Json(new { Error = "Feed not found" });
            }
            var feed = Feed.ById(id);
            if (feed == null)
            {
                Response.StatusCode = 404;
                return Json(new { Error = "Feed not found" });
            }
            new ReadFeeds().Read(feed);
            Pierce.Feeds.Insert(feed);
            return Json(feed);
        }

        public ActionResult MarkRead(string feedId, string articleId)
        {
            var user = GetUser();
            Subscription sub = user.GetSubscription(feedId);
            if (sub == null)
                return Json(new { Error = "Feed not found" });
            sub.Read(articleId);
            Pierce.Users.Save(user);
            return Json(new { Success = true });
        }

        public ActionResult All()
        {
            var user = GetUser();
            if (user == null)
                return Json(new {Error = "you are not logged in"});
            var feeds = new List<Feed>();
            foreach (var sub in user.Subscriptions)
            {
                feeds.Add(Feed.ById(sub.FeedId));
            }
            return Json(feeds);
        }

        public ActionResult List()
        {
            return Json(new {});
        }
    }
}