using System;
using System.Collections.Generic;
using System.Linq;
using MongoDB.Bson;
using MongoDB.Driver.Builders;
using MongoDB.Bson.Serialization.Attributes;

namespace pierce
{
    [BsonIgnoreExtraElements]
    public class Feed
    {
        public static readonly TimeSpan MinUpdateInterval = TimeSpan.FromMinutes(15);
        public static readonly TimeSpan MaxUpdateInterval = TimeSpan.FromDays(14);


        [BsonId, BsonRepresentation(BsonType.ObjectId)]
        public string Id;
        public string HeadChunkId;
        
        // URL for the RSS feed -- where we get the actual XML document.
        public Uri Uri;

        // Values provided by the feed itself.
        public string Title;
        public Uri Link;
        public string Description;
        public ICollection<string> Categories = new HashSet<string>();
        public Uri LogoUri;
        public Uri IconUri;
        public Uri ImageLinkTarget;
        public string ImageTitle;
        public List<Article> Articles = new List<Article>();
        public List<Author> Authors = new List<Author>();
        public List<string> ChunkIds = new List<string>();
        public DateTime LastRead = DateTime.MinValue;
        public TimeSpan ReadInterval = TimeSpan.FromHours(1);
        public DateTime NextRead = DateTime.MinValue;
        public int Errors = 0;
        public int ArticleCount = 0;
        [BsonIgnore]
        private List<Chunk> _chunkCache = new List<Chunk>();
        [BsonIgnore]
        private Chunk _head;

        // Deprecated.
        public Chunk Head;

        [BsonIgnore]
        public Chunk HeadChunk
        {
            get
            {
                if (string.IsNullOrEmpty(HeadChunkId))
                {
                    HeadChunkId = ChunkIds.LastOrDefault();
                    if (string.IsNullOrEmpty(HeadChunkId))
                    {
                        var headChunk = new Chunk { FeedId = Id };
                        CacheChunk(headChunk);
                        HeadChunkId = headChunk.Id;
                        return headChunk;
                    }
                }
                var chunk = GetChunk(HeadChunkId);
                if (chunk == null)
                {
                    chunk = new Chunk { FeedId = Id };
                    HeadChunk = chunk;
                    return chunk;
                }
                return chunk;
            }
            set
            {
                _head = value;
                // TODO set Start to a sensible value
                HeadChunkId = value.Id;
                CacheChunk(value);

            }
        }
        
        public Article GetArticle(string uniqueId)
        {
            return Articles.Where(x => x.UniqueId == uniqueId).FirstOrDefault();
        }

        public Feed ToHeader()
        {
            var header = (Feed)this.MemberwiseClone();
            header.Articles = null;
            return header;
        }

        public Chunk GetChunk(string id)
        {
            return _chunkCache.Where(x => x.Id == id).FirstOrDefault() ?? Chunk.ById(id);
        }

        public void CacheChunk(Chunk chunk)
        {
            if (!string.IsNullOrWhiteSpace(chunk.Id) && _chunkCache.Any(x => x.Id == chunk.Id))
            {
                throw new InvalidOperationException(string.Format("Attempted to re-cache cached chunk {0}", chunk.Id));
            }
            _chunkCache.Add(chunk);
        }

        public void Save()
        {
            if (string.IsNullOrEmpty(Id))
            {
                // Ensure we have an id that we can set for our chunks.
                Pierce.Feeds.Save(this);
            }
            foreach (var chunk in _chunkCache.Where(x => !x.Articles.Any()))
            {
                ChunkIds.Remove(chunk.Id);
            }
            foreach (var chunk in _chunkCache.Where(x => x.Articles.Any()).OrderBy(x => x.Articles.First().PublishDate))
            {
                chunk.FeedId = this.Id;
                chunk.Save();
                if (!ChunkIds.Contains(chunk.Id))
                {
                    ChunkIds.Add(chunk.Id);
                }
            }
            if (_head != null)
            {
                if (string.IsNullOrWhiteSpace(_head.Id))
                {
                    _head = null;
                    HeadChunkId = ChunkIds.LastOrDefault();
                }
                else if (HeadChunkId != _head.Id)
                {
                    HeadChunkId = _head.Id;
                }
            }
            Pierce.Feeds.Save(this);
        }

        public override string ToString()
        {
            return string.Format("[Feed: Id={0}, Uri={1}, Title={2}]", Id, Uri, Title);
        }

        public static Feed ById(string id)
        {
            return Pierce.Feeds.Find(Query.EQ("_id", new ObjectId(id))).FirstOrDefault();
        }
 
        public static Feed ByUri(string uri)
        {
            return Pierce.Feeds.Find(Query.EQ("Uri", uri)).FirstOrDefault();
        }
    }
}
