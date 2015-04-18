using System;
using System.Linq;
using MongoDB.Driver.Builders;
using MongoDB.Bson;

namespace pierce
{
	public class SubscriptionsHandler : IFeedTask
	{
		private readonly Mongo _db;
		private readonly PierceConfig _config;

		public SubscriptionsHandler(Mongo db, PierceConfig config)
		{
			_db = db;
			_config = config;
		}

		public float Priority { get { return 0; } }

		public bool Update(Feed feed)
		{
			// Potential race condition: 
			var users = _db.Users.Find(Query.ElemMatch("Subscriptions", Query.EQ("FeedId", new ObjectId(feed.Id)))).ToList();
			if (!users.Any())
			{
				_db.Feeds.Remove(Query.EQ("_id", new ObjectId(feed.Id)));
				_db.Chunks.Remove(Query.EQ("FeedId", new ObjectId(feed.Id)));
				return false;
			}
			var interval = users
                .Select(x => x.GetSubscription(feed.Id))
                .Where(x => x != null)
                .Select(x => x.CheckInterval)
                .Min();
			if (interval < _config.MinUpdateInterval)
			{
				interval = _config.MinUpdateInterval;
			}
			feed.ReadInterval = interval;
			return true;
		}
	}
}
