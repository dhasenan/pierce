using System;
using System.Linq;
using MongoDB.Driver.Builders;
using MongoDB.Bson;

namespace pierce
{
    public class GarbageCollector : IFeedTask
    {
        public float Priority { get { return 0; } }

        public bool Update(Feed feed)
        {
            var users = Pierce.Users.Find(Query.ElemMatch("Subscriptions", Query.EQ("FeedId", new ObjectId(feed.Id)))).ToList();
            if (!users.Any())
            {
                Pierce.Feeds.Remove(Query.EQ("_id", new ObjectId(feed.Id)));
                Pierce.Chunks.Remove(Query.EQ("FeedId", new ObjectId(feed.Id)));
                return false;
            }
            var interval = users
                .Select(x => x.GetSubscription(feed.Id))
                .Where(x => x != null)
                .Select(x => x.CheckInterval)
                .Min();
            feed.ReadInterval = interval;
            return true;
        }
    }
}
