using System;
using System.Collections.Generic;
using System.Linq;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace pierce
{
    public class Article
    {
        // Id is our internal, globally unique ID; UniqueId is (supposedly) unique to the feed.
        [BsonRepresentation(BsonType.String)]
        public Guid Id = Guid.NewGuid();
        public DateTime PublishDate;
        public Uri Link;
        public Uri CommentLink;
        public string Title;
        public string Description;
        public ICollection<string> Categories = new HashSet<string>();
        public ICollection<Author> Authors = new HashSet<Author>();
        public string UniqueId;
        public string Summary;
        public string ChunkId;
        
        public override string ToString()
        {
            return string.Format("[Article: PublishDate={0}, Title={1}, Description={2}, UniqueId={3}]",
                                 PublishDate, Title, Description, UniqueId);
        }
    }
}

