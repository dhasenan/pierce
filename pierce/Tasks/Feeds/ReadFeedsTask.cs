using System;
using Castle.Core.Logging;

namespace pierce
{
    public class ReadFeedsTask : IFeedTask
    {
        
        private readonly ReadFeeds _reader;

        public ReadFeedsTask(ReadFeeds reader)
        {
            _reader = reader;
        }

        public float Priority { get { return 500; } }

        public bool Update(Feed feed)
        {
            _reader.Read(feed);
            return true;
        }
    }
}

