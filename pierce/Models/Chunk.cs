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
        public string
            Id;
        public List<Article> Articles = new List<Article>();
        public string FeedId;
        public DateTime Start = DateTime.MinValue;
        [BsonIgnore]
        private Guid objectId = Guid.NewGuid();

        public Article GetArticle(string uniqueId)
        {
            return Articles.Where(x => x.UniqueId == uniqueId).FirstOrDefault();
        }

        public static Chunk ById(string chunkId)
        {
            return Pierce.Chunks.FindOneById(new ObjectId(chunkId));
        }
        
        public void AddArticle(Article article)
        {
            if (Start > article.PublishDate)
            {
                return;
            }
            foreach (var existing in Articles.Where(x => x.UniqueId == article.UniqueId).ToList())
            {
                Articles.Remove(existing);
                article.Id = existing.Id;
                article.PublishDate = existing.PublishDate;
            }
            Articles.Add(article);
            article.ChunkId = Id;
            if (Articles.Any(x => x.PublishDate > article.PublishDate))
            {
                Articles = Articles.OrderBy(x => x.PublishDate).ToList();
            }
        }

        public void Save()
        {
            if (Articles.Any())
            {
                Start = Articles [0].PublishDate;
            }
            bool noId = string.IsNullOrEmpty(Id);
            Pierce.Chunks.Save(this);
            if (noId)
            {
                foreach (var article in Articles)
                {
                    article.ChunkId = Id;
                }
                Pierce.Chunks.Save(this);
            }
        }
    }
}

