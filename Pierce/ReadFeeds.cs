using System;
using Microsoft.Extensions.Logging;
using Microsoft.EntityFrameworkCore;

namespace Pierce;

public class ReaderService : BackgroundService
{
    private readonly IServiceProvider _services;
    private readonly ILogger _logger;

    public ReaderService(IServiceProvider services, ILogger<ReaderService> logger)
    {
        _services = services;
        _logger = logger;
        _logger.LogInformation("ReaderService created");
    }

    protected override async Task ExecuteAsync(CancellationToken token)
    {
        _logger.LogInformation("ExecuteAsync");
        while (!token.IsCancellationRequested)
        {
            using (var scope = _services.CreateScope())
            {
                var readFeeds = scope.ServiceProvider.GetRequiredService<ReadFeeds>();
                await readFeeds.Read();
            }
            await Task.Delay(TimeSpan.FromMinutes(1), token);
        }
    }
}

public class ReadFeeds
{
    private readonly PierceContext _db;
    private readonly Wget _wget;
    private readonly FeedParser _parser;
    private readonly ILogger<ReadFeeds> _logger;

    public ReadFeeds(PierceContext db, Wget wget, FeedParser parser, ILogger<ReadFeeds> logger)
    {
        _db = db;
        _wget = wget;
        _parser = parser;
        _logger = logger;
    }

    public async Task Read()
    {
      var now = DateTime.UtcNow;
      var feeds = _db.Feeds
        .Include(x => x.Articles)
        .Where(x => x.NextRead < now)
        .OrderBy(x => x.NextRead)
        .ToList();
      _logger.LogInformation($"have {feeds.Count} feeds to read before {now}");
      foreach (var feed in feeds)
      {
        try
        {
          _logger.LogInformation($"reading feed {feed.Id} at {feed.Uri} with {feed.Articles.Count} articles so far");
          await Read(feed);
        }
        catch (Exception ex)
        {
            _logger.LogError($"while reading feed {feed.Id} {feed.Uri}", ex);
        }
        finally
        {
          feed.NextRead = DateTime.UtcNow + feed.ReadInterval;
          foreach (var article in feed.Articles)
          {
              if (article.Id == 0)
              {
                  _db.Update(article);
              }
          }
          _db.Update(feed);
          _db.SaveChanges();
        }
          _logger.LogInformation($"feed has {feed.Articles.Count} articles");
      }
    }

    public async Task Read(Feed feed)
    {
        _logger.LogTrace($"reading feed {feed.Id} from {feed.Uri}");
        var xml = await _wget.Xml(feed.Uri);
        _parser.Read(feed, xml);
    }
}
