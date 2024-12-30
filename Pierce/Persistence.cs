using Microsoft.EntityFrameworkCore;
using System;
using System.Collections.Generic;
using EFCore.NamingConventions;

namespace Pierce;

public class PierceContext : DbContext
{
  public DbSet<User> Users { get; set; }
  public DbSet<Feed> Feeds { get; set; }
  public DbSet<Article> Articles { get; set; }
  public DbSet<Subscription> Subscriptions { get; set; }

  private readonly string _connectionString;

  public PierceContext(IConfiguration config)
  {
    _connectionString = config.GetConnectionString("pierce");
  }

  protected override void OnConfiguring(DbContextOptionsBuilder builder)
  {
    builder
      .UseSqlite(_connectionString)
      .UseSnakeCaseNamingConvention()
      .LogTo(Console.WriteLine, new[]{DbLoggerCategory.Database.Command.Name});
  }

  protected override void OnModelCreating(ModelBuilder builder)
  {
    builder.Entity<User>()
      .HasMany(e => e.Subscriptions)
      .WithOne(e => e.User)
      .HasForeignKey(e => e.UserId)
      .IsRequired();
    builder.Entity<Article>().OwnsOne(article => article.AuthorInfo, ownedBuilder =>
    {
      ownedBuilder.ToJson();
      ownedBuilder.OwnsMany(x => x.Authors);
    });
    builder.Entity<Feed>().OwnsOne(feed => feed.AuthorInfo, ownedBuilder =>
    {
      ownedBuilder.ToJson();
      ownedBuilder.OwnsMany(x => x.Authors);
    });
    builder.Entity<Feed>()
      .HasMany(e => e.Articles)
      .WithOne(e => e.Feed)
      .HasForeignKey(e => e.FeedId)
      .IsRequired();
    builder.Entity<Feed>()
      .HasMany(e => e.Subscriptions)
      .WithOne(e => e.Feed)
      .HasForeignKey(e => e.FeedId)
      .IsRequired();
  }
}
