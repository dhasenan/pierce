using System;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Collections.Generic;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace pierce
{
    public class User
    {
        [BsonId]
        [BsonRepresentation(BsonType.ObjectId)]
        public string Id;
        public string Email;
        public string PasswordHash;
        public ICollection<Subscription> Subscriptions = new HashSet<Subscription>();
        public string Password { set { PasswordHash = HashedPassword(value); } }

        public Subscription GetSubscription(string objectId)
        {
            return Subscriptions.Where(x => x.FeedId == objectId).FirstOrDefault();
        } 

        public void SubscribeTo(Feed f)
        {
            Subscriptions.Add(new Subscription { FeedUri = f.Uri, FeedId = f.Id });
            f.Subscribers.Add(Id);
        }

        public static string HashedPassword(string password)
        {
            var hash = HashAlgorithm.Create("SHA1");
            return hash.ComputeHash(Encoding.UTF8.GetBytes(password))
                    .Select(x => string.Format("{0:x}", x))
                    .Aggregate((x, y) => x + y);
        }
    }
}