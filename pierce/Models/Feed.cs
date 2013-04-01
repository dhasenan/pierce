using System;
using System.Collections.Generic;
using System.Linq;
using MongoDB.Bson;
using MongoDB.Driver.Builders;
using MongoDB.Bson.Serialization.Attributes;

namespace pierce
{
    public class Feed
    {
        public static readonly TimeSpan MinUpdateInterval = TimeSpan.FromMinutes(15);
        public static readonly TimeSpan MaxUpdateInterval = TimeSpan.FromDays(14);
        [BsonId]
        [BsonRepresentation(BsonType.ObjectId)]
        public string
            Id;
        
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
        public ICollection<Article> Articles = new HashSet<Article>();
        public ICollection<Author> Authors = new HashSet<Author>();
        public DateTime LastRead = DateTime.MinValue;
        public TimeSpan ReadInterval = TimeSpan.FromHours(1);
        public DateTime NextRead = DateTime.MinValue;
        public int Errors = 0;
        
        public Article GetArticle(string uniqueId)
        {
            return Articles.Where(x => x.UniqueId == uniqueId).FirstOrDefault();
        }

        public void AddArticle(Article article)
        {
            if (!string.IsNullOrWhiteSpace(article.UniqueId))
            {
                foreach (var existing in Articles.Where(x => x.UniqueId == article.UniqueId).ToList())
                {
                    Articles.Remove(existing);
                }
            }
            Articles.Add(article);
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