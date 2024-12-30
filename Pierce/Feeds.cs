using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;
using System.Net;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;

namespace Pierce;

[Index(nameof(UserId), nameof(FeedId), IsUnique = true)]
[Index(nameof(FeedId))]
public class Subscription
{
  [Key]
  [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
  public long Id { get; set; }

  [ForeignKey(nameof(Feed))]
  public long FeedId { get; set; }
  public Feed Feed { get; set; }

  [ForeignKey(nameof(User))]
  public long UserId { get; set; }
  public User User { get; set; }

  public TimeSpan Interval { get; set; }
}

[Index(nameof(FeedId), nameof(PublishDate))]
public class Article
{
  [Key]
  [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
  public long Id { get; set; }

  [ForeignKey(nameof(Feed))]
  public long FeedId { get; set; }
  public Feed Feed { get; set; }

  public DateTime PublishDate { get; set; }
  public Uri? Link { get; set; }
  public Uri? CommentLink { get; set; }
  public string Title { get; set; } = "";
  public string Description { get; set; }
  public IList<string> Categories { get; set; } = new List<string>();
  public AuthorInfo AuthorInfo { get; set; } = new AuthorInfo();
  public string? UniqueId { get; set; }
  public string? Summary { get; set; }
}

[Index(nameof(Uri), IsUnique = true)]
public class Feed
{
  public static readonly TimeSpan MinUpdateInterval = TimeSpan.FromMinutes(15);
  public static readonly TimeSpan DefaultUpdateInterval = TimeSpan.FromMinutes(15);
  public static readonly TimeSpan MaxUpdateInterval = TimeSpan.FromDays(14);

  [Key]
  [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
  public long Id { get; set; }

  // URL for the RSS feed -- where we get the actual XML document.
  [Required]
  public Uri Uri { get; set; }

  public Feed(Uri uri)
  {
    this.Uri = uri;
  }

  // Values provided by the feed itself.
  public string Title { get; set; } = "";
  public Uri? Link { get; set; }
  public string? Description { get; set; }
  public IList<string> Categories { get; set; } = new List<string>();
  public Uri? LogoUri { get; set; }
  public Uri? IconUri { get; set; }
  public Uri? ImageLinkTarget { get; set; }
  public string? ImageTitle { get; set; }
  public DateTime LastRead { get; set; } = DateTime.MinValue;
  public TimeSpan ReadInterval { get; set; } = TimeSpan.FromHours(1);
  public DateTime NextRead { get; set; } = DateTime.MinValue;
  public int Errors { get; set; } = 0;
  public int ArticleCount { get; set; } = 0;

  public AuthorInfo AuthorInfo { get; set; } = new AuthorInfo();

  public IList<Subscription> Subscriptions { get; set; } = new List<Subscription>();
  public IList<Article> Articles { get; set; } = new List<Article>();

  public Feed Redacted()
  {
    var f = (Feed) MemberwiseClone();
    f.Articles = new List<Article>();
    f.Subscriptions = new List<Subscription>();
    return f;
  }
}

public class AuthorInfo
{
  public List<Author> Authors { get; set; } = new List<Author>();
}

public class Author
{
  public string Name { get; set; }
  public Uri? Link { get; set; }
  public string? Email { get; set; }

  public override bool Equals(object obj)
  {
    if (obj == null)
      return false;
    if (ReferenceEquals(this, obj))
      return true;
    if (obj.GetType() != typeof(Author))
      return false;
    Author other = (Author)obj;
    return Name == other.Name;
  }

  public override int GetHashCode()
  {
    unchecked
    {
      return (Name != null ? Name.GetHashCode() : 0);
    }
  }
}


[Route("feeds")]
[ApiController]
[Authorize(Policy = Auth.Policy)]
public class FeedsController : Controller
{
  private readonly PierceContext db;
  private readonly AutodetectFeeds _autodetectFeeds;

  public FeedsController(PierceContext db, AutodetectFeeds autodetectFeeds)
  {
    this.db = db;
    this._autodetectFeeds = autodetectFeeds;
  }

  [HttpGet("list")]
  public async Task<IActionResult> List()
  {
    Console.WriteLine("hihi!");
    var user = await HttpContext.PierceUser(db);
    var subs =  user.Subscriptions;
    foreach (var sub in subs)
    {
      sub.Feed.Subscriptions = new List<Subscription>();
    }
    return Json(subs);
  }


  public class SubscriptionDetails
  {
    public long? Id { get; set; }
    public TimeSpan? Interval { get; set; }
    public string Uri { get; set; }
  }

  [HttpPost("subscribe")]
  public async Task<IActionResult> Subscribe([FromBody] SubscriptionDetails details)
  {
    if (string.IsNullOrEmpty(details.Uri))
    {
      return BadRequest("invalid Uri");
    }
    var user = await HttpContext.PierceUser(db);
    var uri = new Uri(details.Uri);
    Feed feed = await db.Feeds.SingleOrDefaultAsync(feed => feed.Uri == uri);
    if (feed == null)
    {
      var feeds = await _autodetectFeeds.FromHtmlPage(details.Uri);
      if (feeds.Count == 0)
      {
        return Ok(new { error = "No feed found for URL " + uri});
      }
      feed = feeds[0];
      var existing = await db.Feeds.SingleOrDefaultAsync(feed => feed.Uri == feed.Uri);
      if (existing == null)
      {
        await db.Feeds.AddAsync(feed);
      }
    }
    var subscription = await db.Subscriptions.SingleOrDefaultAsync(sub => sub.FeedId == feed.Id && sub.UserId == user.Id);
    if (subscription != null)
    {
      // nothing to do, you're already subscribed
      return Json(subscription);
    }
    var interval = details.Interval ?? Feed.DefaultUpdateInterval;
    if (interval < Feed.MinUpdateInterval) interval = Feed.MinUpdateInterval;
    if (interval > Feed.MaxUpdateInterval) interval = Feed.MaxUpdateInterval;
    var sub = new Subscription
    {
      UserId = user.Id,
      FeedId = feed.Id,
      Interval = interval,
    };
    await db.AddAsync(sub);

    await db.SaveChangesAsync();

    return Ok(sub);
  }

  [HttpGet("articles")]
  public async Task<IActionResult> Articles(long feedId, DateTime? since)
  {
    throw new Exception("not implemented");
//    var articles = from 
  }
}
