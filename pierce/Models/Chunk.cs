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
        [BsonIgnore]
        private Guid
            objectId = Guid.NewGuid();

        public DateTime Start
        {
            get
            {
                if (Articles.Any())
                {
                    return Articles.Min(x => x.PublishDate);
                }
                return DateTime.MinValue;
            }
            set {}
        }

        public Article GetArticle(string uniqueId)
        {
            return Articles.Where(x => x.UniqueId == uniqueId).FirstOrDefault();
        }

        public static Chunk ById(string chunkId, Mongo db)
        {
            return db.Chunks.FindOneById(new ObjectId(chunkId));
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

        public void Save(Mongo db)
        {
            bool noId = string.IsNullOrEmpty(Id);
            db.Chunks.Save(this);
            if (noId)
            {
                foreach (var article in Articles)
                {
                    article.ChunkId = Id;
                }
                db.Chunks.Save(this);
            }
        }
    }
}

