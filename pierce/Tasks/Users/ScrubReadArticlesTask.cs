using System;
using System.Linq;

namespace pierce
{
    public class ScrubReadArticlesTask
    {
        Mongo _db;

        public ScrubReadArticlesTask(Mongo db)
        {
            _db = db;
        }

        public void Update(User user)
        {
            foreach (var sub in user.Subscriptions)
            {
                var feed = Feed.ById(sub.FeedId, _db);
                var head = feed.GetHeadChunk(_db);
                var deadReads = sub.ReadArticles.Where(x => !head.Articles.Any(y => y.Id.ToString() == x)).ToList();
                foreach (var dead in deadReads)
                {
                    sub.ReadArticles.Remove(dead);
                }
            }
        }
    }
}

