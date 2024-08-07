using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace Pierce;

[Index(nameof(UserId), nameof(FeedId), IsUnique = true)]
[Index(nameof(FeedId))]
public class Subscription
{
  [Key]
  public long Id { get; set; }

  [ForeignKey(nameof(Feed))]
  public long FeedId { get; set; }

  [ForeignKey(nameof(User))]
  public long UserId { get; set; }

  public TimeSpan Interval { get; set; }
}

[Index(nameof(FeedId), nameof(PublishDate))]
public class Article
{
  [Key]
  public long Id { get; set; }

  [ForeignKey(nameof(Feed))]
  public long FeedId { get; set; }
  public Feed Feed { get; set; }

  public DateTime PublishDate { get; set; }
  public Uri Link { get; set; }
  public Uri CommentLink { get; set; }
  public string Title { get; set; }
  public string Description { get; set; }
  public ICollection<string> Categories { get; set; } = new HashSet<string>();
  public AuthorInfo AuthorInfo { get; set; }
  public string UniqueId { get; set; }
  public string Summary { get; set; }
}

[Index(nameof(Uri), IsUnique = true)]
public class Feed
{
  public static readonly TimeSpan MinUpdateInterval = TimeSpan.FromMinutes(15);
  public static readonly TimeSpan MaxUpdateInterval = TimeSpan.FromDays(14);

  [Key]
  public long Id { get; set; }

  // URL for the RSS feed -- where we get the actual XML document.
  [Required]
  public Uri Uri { get; set; }

  // Values provided by the feed itself.
  public string Title { get; set; }
  public Uri Link { get; set; }
  public string Description { get; set; }
  public ICollection<string> Categories { get; set; } = new HashSet<string>();
  public Uri LogoUri { get; set; }
  public Uri IconUri { get; set; }
  public Uri ImageLinkTarget { get; set; }
  public string ImageTitle { get; set; }
  public DateTime LastRead { get; set; } = DateTime.MinValue;
  public TimeSpan ReadInterval { get; set; } = TimeSpan.FromHours(1);
  public DateTime NextRead { get; set; } = DateTime.MinValue;
  public int Errors { get; set; } = 0;
  public int ArticleCount { get; set; } = 0;

  public AuthorInfo AuthorInfo { get; set; }

  public ICollection<Subscription> Subscriptions { get; set; } = new List<Subscription>();
}

public class AuthorInfo
{
  public List<Author> Authors { get; set; } = new List<Author>();
}

public class Author
{
  public string Name { get; set; }
  public Uri Link { get; set; }
  public string Email { get; set; }

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
