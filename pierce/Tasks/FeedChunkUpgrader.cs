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
            if (feed.Articles.Any())
            {
                _logger.InfoFormat("upgrading feed {0} to chunk format", feed);
                if (feed.Head != null && feed.Articles.Any())
                {
                    _logger.WarnFormat("feed {0} has non-empty articles collection and non-empty chunks; trying to merge", feed);
                }
                foreach (var art in feed.Articles)
                {
                    if (feed.Head.GetArticle(art.UniqueId) == null)
                    {
                        feed.Head.Articles.Add(art);
                    }
                }
                feed.ArticleCount += feed.Articles.Count;
                feed.Articles.Clear();
                Pierce.Feeds.Save(feed);
            }
            return true;
        }
    }
}

