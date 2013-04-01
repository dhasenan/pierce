using System;
using System.Collections.Generic;
using MongoDB.Bson;
using System.Linq;

namespace pierce
{
    public class Article
    {
        // Id is our internal, globally unique ID; UniqueId is (supposedly) unique to the feed.
        public Guid Id = Guid.NewGuid();
        public DateTime PublishDate;
        public Uri Link;
        public Uri CommentLink;
        public string Title;
        public string Description;

        public string Author
        {
            get { return Authors.FirstOrDefault(); }
            set
            {
                if (!Authors.Contains(value))
                {
                    Authors.Add(value);
                }
            }
        }

        public ICollection<string> Categories = new HashSet<string>();
        public ICollection<string> Authors = new HashSet<string>();
        public string UniqueId;
        public string Summary;
        
        public override string ToString()
        {
            return string.Format("[Article: PublishDate={0}, Title={1}, Description={2}, UniqueId={3}]",
                                 PublishDate, Title, Description, UniqueId);
        }
    }
}

