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
        public ActionResult Add(string url, string title, string labels)
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
                var sub = user.SubscribeTo(f);
                sub.Labels = GetLabels(labels);
                if (!string.IsNullOrEmpty(title))
                {
                    sub.Title = title;
                }
                Pierce.Users.Save(user);
                Pierce.Feeds.Save(f);
                return Json(new { FoundFeeds = true, AddedFeed = f, Subscription = sub });
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

        static List<string> GetLabels(string labels)
        {
            if (string.IsNullOrEmpty(labels))
            {
                return new List<string>();
            }
            return labels.Split(',').Select(x => x.Trim()).Where(x => !string.IsNullOrEmpty(x)).ToList();
        }

        public ActionResult Update(string id, string title, int checkIntervalSeconds, string labels)
        {
            var user = GetUser();
            if (user == null)
            {
                Response.StatusCode = 401;
                return Json(new { Error = "Not authenticated" });
            }

            // Clamp updateInterval.
            var checkInterval = TimeSpan.FromSeconds(checkIntervalSeconds);
            if (checkInterval > Feed.MaxUpdateInterval)
                checkInterval = Feed.MaxUpdateInterval;
            if (checkInterval < Feed.MinUpdateInterval)
                checkInterval = Feed.MinUpdateInterval;
            var sub = user.GetSubscription(id);
            var feed = Feed.ById(id);
            if (feed == null)
            {
                return Json(new { Error = "We couldn't find your feed! We tried recreating it for you, but we couldn't. Is the site working?" });
            }
            if (sub == null)
            {
                // not subscribed to the feed -- fix this
                user.SubscribeTo(feed);
                sub = user.GetSubscription(feed.Id);
            }
            sub.CheckInterval = checkInterval;
            if (sub.CheckInterval < feed.ReadInterval)
            {
                feed.ReadInterval = sub.CheckInterval;
                feed.NextRead = feed.LastRead + feed.ReadInterval;
                Pierce.Feeds.Save(feed);
            }
            if (title != feed.Title)
            {
                sub.Title = title;
            }
            sub.Labels = GetLabels(labels);
            Pierce.Users.Save(user);
            return Json(new { Feed = feed, Subscription = sub });
        }

        public ActionResult RefreshNow(string id)
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
            Pierce.Feeds.Save(feed);
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
    }
}