using System;

namespace Pierce;

public class CheckFeeds
{
  private readonly PierceContext _db;
  private readonly ReadFeeds _reader;
  public CheckFeeds(PierceContext db, ReadFeeds reader)
  {
    _db = db;
    _reader = reader;
  }

  public async void Run()
  {
    // find the feeds that ought to run now
    var now = DateTime.UtcNow;
    while (true)
    {
    }
  }
}
