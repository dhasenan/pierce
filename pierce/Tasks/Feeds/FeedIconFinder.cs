using System;

namespace pierce
{
    public class FeedIconFinder : IFeedTask
    {
        FindIcon _findIcon;

        public FeedIconFinder(FindIcon findIcon)
        {
            _findIcon = findIcon;
        }

        public float Priority { get { return 1000; } }

        public bool Update(Feed feed)
        {
            if (feed.IconUri == null)
            {
                feed.IconUri = _findIcon.Find(feed.Uri);
            }
            return true;
        }
    }
}

