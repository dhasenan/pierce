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
        private readonly Mongo _db;
        ILogger _logger;

        public FeedMaintenance(IFeedTask[] tasks, Mongo db, ILogger logger)
        {
            _tasks = tasks.OrderBy(task => task.Priority).ToList();
            _db = db;
            _logger = logger;
        }
        
        public void Execute()
        {
            // TODO batch these rather than reading everything
			// TODO: this seems to be getting everything every time. Why?
			var list = _db.Feeds.Find(Query.LT("NextRead", DateTime.UtcNow));
			foreach (var feed in list)
            {
				if (feed.NextRead > DateTime.UtcNow)
				{
					_logger.WarnFormat("got feed {0}, but it's not scheduled for update until {1}", feed, feed.NextRead);
					continue;
				}
				var oldLastRead = feed.LastRead;
				var oldNextRead = feed.NextRead;
                ExecuteSingle(feed);
				_logger.InfoFormat("feed was [last read: {0} next read: {1}] now is: [last read: {2} next read: {3}] (read interval {4}",
					oldLastRead, oldNextRead, feed.LastRead, feed.NextRead, feed.ReadInterval);
            }
        }

        public void ExecuteSingle(Feed feed)
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
                    _logger.ErrorFormat("failed to run task {0} on feed {1}: {2}", task, feed, ex);
                    feed.Errors++;
                }
            }
            feed.LastRead = DateTime.UtcNow;
			feed.NextRead = DateTime.UtcNow + feed.ReadInterval;
            feed.Save(_db);
        }
    }
}

