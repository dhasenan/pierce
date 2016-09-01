using System;
using System.Linq;
using MongoDB.Driver.Builders;
using Castle.Core.Logging;

namespace pierce
{
    public class UserMaintenance
    {
        public static readonly TimeSpan CheckInterval = TimeSpan.FromHours(1);

        Mongo _db;
        ILogger _logger;
        ScrubReadArticlesTask _task;

        public UserMaintenance(Mongo db, ScrubReadArticlesTask task, ILogger logger)
        {
            _db = db;
            _task = task;
            _logger = logger;
        }

        public void Execute()
        {
            var noMaintenanceSet = _db.Users.Find(Query.NotExists("NextMaintenance"));
            Update(noMaintenanceSet);
            var maintenanceNow = _db.Users.Find(Query.LT("NextMaintenance", DateTime.UtcNow));
            Update(maintenanceNow);
        }

        void Update(MongoDB.Driver.MongoCursor<User> maintenanceNow)
        {
            foreach (var user in maintenanceNow)
            {
                _logger.InfoFormat("handling user {0}", user.Id);
                _task.Update(user);
                user.NextMaintenance = DateTime.UtcNow + CheckInterval;
                _db.Users.Save(user);
            }
        }
    }
}

