using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;
using MongoDB.Bson;

namespace pierce
{
    public class Subscription
    {
        public Uri FeedUri;

        // User-set title, defaulting to feed title.
        public string Title;
        public ObjectId FeedId;
        public TimeSpan CheckInterval = TimeSpan.FromHours(1);
        public ICollection<string> ReadArticles = new HashSet<string>();
        // TODO(dhasenan) how many historical ones to keep, how old in the past, etc

        public void Read(string article)
        {
            if (!ReadArticles.Contains(article))
            {
                ReadArticles.Add(article);
            }
        }
    }

}

