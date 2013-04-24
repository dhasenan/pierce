using System;
using System.Collections.Generic;
using System.Linq;
using MongoDB.Driver.Builders;
using Castle.Core.Logging;

namespace pierce
{
    public class FeedMaintenance
    {
        ICollection<IFeedTask> _tasks;
        ILogger _logger;

        public FeedMaintenance(IFeedTask[] tasks, ILogger logger)
        {
            _tasks = tasks.OrderBy(task => task.Priority).ToList();
            _logger = logger;
        }
        
        public void Execute()
        {
            // TODO batch these rather than reading everything
            var list = Pierce.Feeds.Find(Query.LT("NextRead", DateTime.UtcNow));
            foreach (var feed in list)
            {
                ExecuteSingle(feed);
            }
        }

        private void ExecuteSingle(Feed feed)
        {
            foreach (var task in _tasks)
            {
                try
                {
                    _logger.InfoFormat("running task {0} on feed {1}", task, feed);
                    if (!task.Update(feed))
                    {
                        return;
                    }
                }
                catch (Exception ex)
                {
                    _logger.ErrorFormat("failed to run task {0} on feed {1}", task, feed, ex);
                    feed.Errors++;
                }
            }
            feed.LastRead = DateTime.UtcNow;
            feed.NextRead = feed.LastRead + feed.ReadInterval;
            Pierce.Feeds.Save(feed);
        }
    }
}

