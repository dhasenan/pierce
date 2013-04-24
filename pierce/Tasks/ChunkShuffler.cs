using System;
using System.Linq;
using Castle.Core.Logging;

namespace pierce
{
    public class ChunkShuffler : IFeedTask
    {
        public const int MaxArticlesPerChunk = 50;
        private readonly ILogger _logger;

        public ChunkShuffler(ILogger logger)
        {
            _logger = logger;
        }

        public float Priority { get { return 1000; } }

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
            }
            while (feed.Head.Articles.Count > MaxArticlesPerChunk)
            {
                _logger.InfoFormat("reshuffling chunks for feed {0}", feed);
                var oldHead = feed.Head;
                feed.Head = new Chunk();
                oldHead.Articles = feed.Head.Articles.OrderBy(x => x.PublishDate).Take(MaxArticlesPerChunk).ToList();
                feed.Head.Articles = feed.Head.Articles.OrderBy(x => x.PublishDate).Skip(MaxArticlesPerChunk).ToList();
                feed.Head.FeedId = feed.Id;
                // If this chunk was the starting chunk, the feed id might not have been set.
                oldHead.FeedId = feed.Id;
                Pierce.Chunks.Save(oldHead);
                feed.ChunkIds.Add(oldHead.Id);
            }
            Pierce.Feeds.Save(feed);
            return true;
        }
    }
}

