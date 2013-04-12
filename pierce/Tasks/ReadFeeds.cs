
using System;
using System.Linq;
using System.Collections.Generic;
using System.Net;
using System.IO;
using System.Xml;
using System.Xml.Linq;
using System.Xml.XPath;
using MongoDB.Driver.Builders;
using System.Globalization;
using MongoDB.Bson;
using log4net;
using Castle.Core.Logging;

namespace pierce
{
    public class ReadFeeds
    {
        private readonly ILogger _logger;
        private readonly Wget _wget;
        private readonly FeedParser _parser;
        private readonly FindIcon _iconFinder;

        public ReadFeeds(Wget wget, FeedParser parser, FindIcon iconFinder, ILogger logger)
        {
            _wget = wget;
            _parser = parser;
            _iconFinder = iconFinder;
            _logger = logger;
        }

        public void Execute()
        {
            var list = Pierce.Feeds.Find(Query.LT("NextRead", DateTime.UtcNow));
            foreach (var feed in list)
            {
                // We should have a sort of feed maintenance task that goes
                // through each feed in sequence and runs a number of subtasks
                // on each, rather than sneaking in this maybe-delete and the
                // update-feed-interval stuff all in the name of reading the
                // latest stories from the webs.
                if (MaybeGarbageCollect(feed))
                {
                    continue;
                }
                try
                {
                    Read(feed);
                }
                catch (Exception ex)
                {
                    _logger.WarnFormat("while handling feed {0}: {1}", feed.Uri, ex);
                    feed.Errors++;
                }
                Pierce.Feeds.Save(feed);
            }
        }

        private bool MaybeGarbageCollect(Feed feed)
        {
            var users = Pierce.Users.Find(Query.ElemMatch("Subscriptions", Query.EQ("FeedId", new ObjectId(feed.Id)))).ToList();
            if (!users.Any())
            {
                Pierce.Feeds.Remove(Query.EQ("_id", new ObjectId(feed.Id)));
                return true;
            }
            var interval = users
                .Select(x => x.GetSubscription(feed.Id))
                .Where(x => x != null)
                .Select(x => x.CheckInterval)
                .Min();
            feed.ReadInterval = interval;
            return false;
        }

        public void Read(Feed feed)
		{
			if (feed.IconUri == null)
			{
				feed.IconUri = _iconFinder.Find(feed.Uri);
			}
            _logger.InfoFormat("reading feed {0} from {1}", feed.Id, feed.Uri);
            var xml = _wget.Xml(feed.Uri);
            _parser.Read(feed, xml);
            feed.LastRead = DateTime.UtcNow;
            feed.NextRead = feed.LastRead + feed.ReadInterval;
        }
    }
}