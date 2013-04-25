using System;
using Castle.Core.Logging;

namespace pierce
{
    public class ReadFeedsTask : IFeedTask
    {
        
        private readonly ILogger _logger;
        private readonly ReadFeeds _reader;

        public ReadFeedsTask(ReadFeeds reader, ILogger logger)
        {
            _reader = reader;
            _logger = logger;
        }

        public float Priority { get { return 500; } }

        public bool Update(Feed feed)
        {
            _reader.Read(feed);
            return true;
        }
    }
}

