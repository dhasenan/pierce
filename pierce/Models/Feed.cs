using System;
using System.Collections.Generic;
using System.Linq;
using MongoDB.Bson;
using MongoDB.Driver.Builders;

namespace pierce
{
	public class Feed
	{
        public ObjectId Id;
		
		// URL for the RSS feed -- where we get the actual XML document.
		public Uri Uri;

		// Values provided by the feed itself.
		public string Title;
		public Uri Link;
		public string Description;
		public ICollection<string> Categories = new HashSet<string>();

		public Uri ImageUri;
		public Uri ImageLinkTarget;
		public string ImageTitle;
        
        public ICollection<Article> Articles = new HashSet<Article>();
        public ICollection<ObjectId> Subscribers = new HashSet<ObjectId>();
		public DateTime LastRead = DateTime.MinValue;
		public TimeSpan ReadInterval = TimeSpan.FromHours(1);
		public int Errors = 0;
		
		public Article GetArticle(string uniqueId)
		{
			return Articles.Where(x => x.UniqueId == uniqueId).FirstOrDefault();
		}

        public long NextUpdateTimestamp
        {
            get { return Timestamp(LastRead + ReadInterval); }
        }

        public Feed SanitizeFor(ObjectId userId)
        {
            var f = (Feed)MemberwiseClone();
            f.Articles = Articles.Select(x => x.SanitizeFor(userId)).ToList();
            return f;
        }

        public override string ToString()
        {
            return string.Format("[Feed: Id={0}, Uri={1}, Title={2}]", Id, Uri, Title);
        }

        public static long Timestamp(DateTime date)
        {
            return (long)(date - new DateTime(1970, 1, 1)).TotalSeconds;
        }

        public static Feed ById(string id)
        {
            return Pierce.Feeds.Find(Query.EQ("_id", new ObjectId(id))).FirstOrDefault();
        }
	}
}