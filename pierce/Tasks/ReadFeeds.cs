using System;
using Castle.Core.Logging;

namespace pierce
{
    public class ReadFeeds : IFeedTask
    {
        private readonly ILogger _logger;
        private readonly Wget _wget;
        private readonly FeedParser _parser;

        public ReadFeeds(Wget wget, FeedParser parser, ILogger logger)
        {
            _wget = wget;
            _parser = parser;
            _logger = logger;
        }

        public float Priority { get { return 500; } }

        public bool Update(Feed feed)
        {
            _logger.InfoFormat("reading feed {0} from {1}", feed.Id, feed.Uri);
            var xml = _wget.Xml(feed.Uri);
            _parser.Read(feed, xml);
            Pierce.Feeds.Save(feed);
            return true;
        }
    }
}