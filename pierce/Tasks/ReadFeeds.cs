using System;
using System.Linq;
using System.Collections.Generic;
using System.Net;
using System.IO;
using System.Xml;
using System.Xml.Linq;
using MongoDB.Driver.Builders;
using System.Globalization;

namespace pierce
{
    // TODO(dhasenan): Atom feeds; RSS1.0
    public class ReadFeeds
    {
        public void Execute()
        {
            var list = Pierce.Feeds.Find(Query.LT("NextRead", DateTime.UtcNow));
            foreach (var feed in list)
            {
                if (feed.NextRead > DateTime.UtcNow)
                {
                    continue;
                }
                try
                {
                    Read(feed);
                }
                catch (Exception ex)
                {
                    Console.WriteLine("while handling feed {0}: {1}", feed.Uri, ex);
                    feed.Errors++;
                }
                Pierce.Feeds.Save(feed);
            }
        }

        public void Read(Feed feed)
        {
            Read(feed, ReadFeedText(feed));
            feed.LastRead = DateTime.UtcNow;
            feed.NextRead = feed.LastRead + feed.ReadInterval;
        }
        
        public TextReader ReadFeedText(Feed feed)
        {
            WebRequest wr = WebRequest.Create(feed.Uri);
            wr.Method = "GET";
            return new StreamReader(wr.GetResponse().GetResponseStream());
        }
        
        private void Elem(XElement element, string descendant, params Action<string>[] setter)
        {
            var v = element.Descendants(descendant).FirstOrDefault();
            if (v == null)
                return;
            foreach (var s in setter)
            {
                try
                {
                    s(v.Value);
                    return;
                }
                catch (Exception ex)
                {
                }
            }
        }

        // The RSS2.0 spec doesn't mandate RFC1123 dates, but it does mention them.
        const string Rfc1123 = "ddd, dd MMM yyyy HH':'mm':'ss";
        const int Rfc1123Length = 25;

        bool TryParseRfc1123(string v, ref DateTime date)
        {
            if (v.Length < Rfc1123Length)
                return false;
            DateTime d;
            if (DateTime.TryParseExact(v.Substring(0, Rfc1123Length), Rfc1123, null, DateTimeStyles.None, out d))
            {
                try
                {
                    TimeZoneInfo tz = TimeZoneInfo.FindSystemTimeZoneById(v.Substring(Rfc1123Length).Trim());
                    d = TimeZoneInfo.ConvertTimeToUtc(d, tz);
                }
                catch (Exception ex)
                {
                    d = d.AddDays(0);
                }
                date = d;
                return true;
            }
            Console.WriteLine("bad date found: {0}", v);
            return false;
        }

        public void Read(Feed feed, TextReader feedText)
        {
            var text = feedText.ReadToEnd();
            Console.WriteLine("reading feed {0}", feed.Uri);
            XDocument x = XDocument.Parse(text);
            var rss = x.Descendants("rss").FirstOrDefault();
            if (rss == null)
            {
                throw new ArgumentException("Feed did not contain an <rss> element.");
            }
            var channel = x.Descendants("channel").FirstOrDefault();
            if (channel == null)
            {
                throw new ArgumentException("Feed did not contain a <channel> element.");
            }
            Elem(channel, "title", v => feed.Title = v);
            Elem(channel, "description", v => feed.Description = v);
            Elem(channel, "link", v => feed.Link = new Uri(v));
            var img = channel.Descendants("image").FirstOrDefault();
            if (img != null)
            {
                Elem(img, "title", v => feed.ImageTitle = v);
                Elem(img, "url", v => feed.ImageUri = new Uri(v));
                Elem(img, "link", v => feed.ImageLinkTarget = new Uri(v));
            }
            foreach (var item in channel.Descendants("item").AsEnumerable())
            {
                var a = new Article();
                a.PublishDate = DateTime.UtcNow;
                Elem(item, "title", v => a.Title = v);
                Elem(item, "author", v => a.Author = v);
                Elem(item, "description", v => a.Description = v);
                Elem(item, "guid", v => a.UniqueId = v);
                Elem(item, "pubDate", v => a.PublishDate = DateTime.Parse(v), v => TryParseRfc1123(v, ref a.PublishDate));
                Elem(item, "link", v => a.Link = new Uri(v));
                Elem(item, "comments", v => a.CommentLink = new Uri(v));
                
                var existing = feed.GetArticle(a.UniqueId);
                if (existing != null)
                {
                    feed.Articles.Remove(existing);
                    if (!item.Descendants("pubDate").Any())
                    {
                        a.PublishDate = existing.PublishDate;
                    }
                }
                if (a.UniqueId == null)
                {
                    // This is crap. It's a better approximation than what we have currently.
                    a.UniqueId = a.Link.ToString();
                }
                feed.Articles.Add(a);
            }
        }
    }
}