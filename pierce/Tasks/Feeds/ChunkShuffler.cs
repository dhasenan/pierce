using System;
using System.Linq;
using Castle.Core.Logging;
using System.Collections.Generic;

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
            // Now, we've already added some articles, maybe.
            // These have been added to the head chunk, which might be oversized.
            // Let's say they haven't been added to feed.Articles.
            var headChunk = feed.HeadChunk;
            while (headChunk.Articles.Count > MaxArticlesPerChunk)
            {
                _logger.InfoFormat("reshuffling chunks for feed {0}", feed);
                var oldHead = headChunk;
                headChunk = new Chunk();
                feed.HeadChunk = headChunk;
                oldHead.Articles = headChunk.Articles.OrderBy(x => x.PublishDate).Take(MaxArticlesPerChunk).ToList();
                headChunk.Articles = headChunk.Articles.OrderBy(x => x.PublishDate).Skip(MaxArticlesPerChunk).ToList();
                _logger.DebugFormat("old head has {0} articles; new has {1}", oldHead.Articles.Count, headChunk.Articles.Count);
            }
            // Okay, let's rebuild feed.Articles.
            feed.Save();
            feed.Articles.Clear();
            List<string> missingChunks = new List<string>();
            foreach (var id in feed.ChunkIds.Where(x => true).Reverse())
            {
                if (feed.Articles.Count >= MaxArticlesPerChunk)
                {
                    _logger.DebugFormat("feed has as much stuff as I really need");
                    break;
                }
                var chunk = feed.GetChunk(id);
                if (chunk != null)
                {
                    _logger.DebugFormat("adding {0} articles from {1}", chunk.Articles.Count, id);
                    feed.Articles.AddRange(chunk.Articles);
                }
                else
                {
                    _logger.DebugFormat("failed to find chunk {0}", id);
                    missingChunks.Add(id);
                }
            }
            feed.ChunkIds.RemoveAll(x => missingChunks.Contains(x));
            feed.Articles = feed.Articles.OrderBy(x => x.PublishDate).Reverse().Take(MaxArticlesPerChunk).Reverse().ToList();
            feed.Save();
            return true;
        }
    }
}

