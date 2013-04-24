using System;
using System.Collections.Generic;
using System.Linq;
using MongoDB.Bson.Serialization.Attributes;
using MongoDB.Bson;

namespace pierce
{
    public class Chunk
    {
        [BsonId]
        [BsonRepresentation(BsonType.ObjectId)]
        public string Id;
        public ICollection<Article> Articles = new HashSet<Article>();
        public string FeedId;

        public Article GetArticle(string uniqueId)
        {
            return Articles.Where(x => x.UniqueId == uniqueId).FirstOrDefault();
        }

        public static Chunk ById(string chunkId)
        {
            return Pierce.Chunks.FindOneById(chunkId);
        }
    }
}

