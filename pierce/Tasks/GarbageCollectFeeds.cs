using System;
using MongoDB.Driver.Builders;

namespace pierce
{
    public class GarbageCollectFeeds
    {
        public GarbageCollectFeeds()
        {
        }

        public void Execute()
        {

            Pierce.Feeds.Remove(Query.Size("Subscribers", 0));
        }
    }
}

