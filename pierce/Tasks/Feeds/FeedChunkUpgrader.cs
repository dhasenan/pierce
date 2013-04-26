using System;
using System.Linq;
using Castle.Core.Logging;

namespace pierce
{
    public class FeedChunkUpgrader : IFeedTask
    {
        ILogger _logger;

        public FeedChunkUpgrader(ILogger logger)
        {
            _logger = logger;
        }

        public float Priority { get { return 10; } }

        public bool Update(Feed feed)
        {
            if (feed.Head != null)
            {
                var head = feed.Head;
                feed.Head = null;
                // This should munge things about appropriately...I think.
                feed.SetHeadChunk(head);
            }
            return true;
        }
    }
}

