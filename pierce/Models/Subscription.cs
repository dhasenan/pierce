using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace pierce
{
    public class Subscription
    {
        public struct ReadArticle
        {
            public string ArticleId;
            public DateTime ArticleDate;
            public string ChunkId;
        }

        // For software upgrades. We want to be able to roll out upgrades as needed, 
        public uint Version = 0;
        public Uri FeedUri;

        // User-set title, defaulting to feed title.
        public string Title;
        [BsonRepresentation(BsonType.ObjectId)]
        public string FeedId;
        public TimeSpan CheckInterval = TimeSpan.FromHours(1);
        // TODO: remove ReadArticles
        public ICollection<string> ReadArticles = new HashSet<string>();
        public IList<ReadArticle> ReadItems = new List<ReadArticle>();
        public ICollection<string> Labels = new HashSet<string>();
        
        // Should be 2 times chunk count; see below.
        public const int MaxReadArticles = 200;

        public void Read(string article)
        {
            if (!ReadArticles.Contains(article))
            {
                ReadArticles.Add(article);
            }
            if (ReadArticles.Count > MaxReadArticles)
            {
            	// They're ordered by read date. If you read 200 articles after this one,
            	// and we only save the most recent 100 articles, we know you can't have
            	// this article in the article list. So we will never show you an article
            	// as unread if you already read it.
            	ReadArticles.RemoveRange(0, ReadArticles.Count - MaxReadArticles);
            }
        }

		public void Unread(string articleId)
		{
			ReadArticles.Remove(articleId);
		}
    }

}

