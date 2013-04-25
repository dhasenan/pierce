using System;
using MongoDB.Bson;
using MongoDB.Driver.Builders;
using Castle.Core.Logging;

namespace pierce
{
    public class OrphanChunkKiller : IFeedTask
    {
        private readonly ILogger _logger;

        public OrphanChunkKiller(ILogger logger)
        {
            _logger = logger;
        }

        public float Priority { get { return 2000; } }

        public bool Update(Feed feed)
        {
            // Race condition:
            //  * User hit "update feed now".
            //  * We added a new chunk.
            //  * We haven't yet saved the new feed, but we saved the chunks.
            // Might be appropriate to have an assigned id for chunks.
            foreach (var chunk in Pierce.Chunks.Find(Query.EQ("FeedId", feed.Id)))
            {
                if (!feed.ChunkIds.Contains(chunk.Id) && feed.HeadChunkId != chunk.Id)
                {
                    _logger.InfoFormat("removing orphan chunk {0}", chunk.Id);
                    Pierce.Chunks.Remove(Query.EQ("_id", new ObjectId(chunk.Id)));
                }
                else if (chunk.Articles.Count == 0)
                {
                    _logger.InfoFormat("removing empty chunk {0}", chunk.Id);
                    feed.ChunkIds.Remove(chunk.Id);
                    Pierce.Chunks.Remove(Query.EQ("_id", new ObjectId(chunk.Id)));
                }
            }
            return true;
        }
    }
}

