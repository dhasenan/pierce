using System;
using MongoDB.Driver;

namespace pierce
{
    public class Mongo
    {
        private static MongoDatabase _db;

        private MongoDatabase DB
        {
            get
            {
                if (_db == null)
                {
                    var client = new MongoClient("mongodb://localhost/pierce");
                    var server = client.GetServer();
                    server.Connect();
                    _db = server.GetDatabase("pierce");
                }
                return _db;
            }
        }

        
        public MongoCollection<User> Users { get { return DB.GetCollection<User>("users"); } }
        
        public MongoCollection<Feed> Feeds { get { return DB.GetCollection<Feed>("feeds"); } }

        public MongoCollection<Chunk> Chunks { get { return DB.GetCollection<Chunk>("chunks"); } }
    }
}

