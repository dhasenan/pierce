using System;

namespace pierce
{
    public interface IFeedTask
    {
        // return value: whether we should continue with other tasks
        bool Update(Feed feed);

        // Lower value: execute sooner
        float Priority { get; }
    }
}

