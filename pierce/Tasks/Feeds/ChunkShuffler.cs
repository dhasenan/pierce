using System;
using System.Linq;
using Castle.Core.Logging;
using System.Collections.Generic;

namespace pierce
{
    public class ChunkShuffler : IFeedTask
    {
        public const int MaxArticlesPerChunk = 50;
        private readonly Mongo _db;
        private readonly ILogger _logger;

        public ChunkShuffler(Mongo db, ILogger logger)
        {
            _db = db;
            _logger = logger;
        }

        public float Priority { get { return 1000; } }

        public bool Update(Feed feed)
        {
            // Now, we've already added some articles, maybe.
            // These have been added to the head chunk, which might be oversized.
            // Let's say they haven't been added to feed.Articles.
            var headChunk = feed.GetHeadChunk(_db);
            _logger.DebugFormat("incoming feed has {0} saved chunks and {1} cached chunks already", feed.ChunkIds.Count, feed.CachedChunkCount);
            while (headChunk.Articles.Count > MaxArticlesPerChunk)
            {
                _logger.InfoFormat("reshuffling chunks for feed {0}", feed);
                var oldHead = headChunk;
                headChunk = new Chunk();
                feed.SetHeadChunk(headChunk);
                headChunk.Articles = oldHead.Articles.OrderBy(x => x.PublishDate).Skip(MaxArticlesPerChunk).ToList();
                oldHead.Articles = oldHead.Articles.OrderBy(x => x.PublishDate).Take(MaxArticlesPerChunk).ToList();
                _logger.DebugFormat("old head has {0} articles; new has {1}", oldHead.Articles.Count, headChunk.Articles.Count);
            }
            feed.Save(_db);
            // Okay, let's rebuild feed.Articles.
            // This is loading way too much data...
            feed.Articles.Clear();
            foreach (var id in feed.ChunkIds)
            {
                var chunk = feed.GetChunk(id, _db);
                if (chunk == null) {
                    _logger.WarnFormat("feed {0} missing chunk {1}", feed.Id, id);
                    continue;
                }
                feed.Articles.AddRange(chunk.Articles);
            }
            feed.Articles = feed.Articles.OrderByDescending(x => x.PublishDate).Take(MaxArticlesPerChunk).Reverse().ToList();
            //feed.Articles = feed.ChunkIds.Select(x => feed.GetChunk(x, _db)).Where(x => x != null).SelectMany(x => x.Articles).OrderByDescending(x => x.PublishDate).Take(MaxArticlesPerChunk).Reverse().ToList();
            feed.Save(_db);
            _logger.DebugFormat("outgoing feed has {0} saved chunks", feed.ChunkIds.Count);
            return true;
        }
    }
}

