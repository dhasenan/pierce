using System;
using Castle.Core.Logging;

namespace pierce
{
    public class ReadFeeds
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

        public void Read(Feed feed)
        {
            _logger.InfoFormat("reading feed {0} from {1}", feed.Id, feed.Uri);
            var xml = _wget.Xml(feed.Uri);
            _parser.Read(feed, xml);
        }
    }
}