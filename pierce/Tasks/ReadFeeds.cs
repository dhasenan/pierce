using System;
using System.Linq;
using System.Collections.Generic;
using System.Net;
using System.IO;
using System.Xml;
using System.Xml.Linq;
using System.Xml.XPath;
using MongoDB.Driver.Builders;
using System.Globalization;
using MongoDB.Bson;

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
                // We should have a sort of feed maintenance task that goes
                // through each feed in sequence and runs a number of subtasks
                // on each, rather than sneaking in this maybe-delete and the
                // update-feed-interval stuff all in the name of reading the
                // latest stories from the webs.
                if (MaybeGarbageCollect(feed))
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

        bool MaybeGarbageCollect(Feed feed)
        {
            var users = Pierce.Users.Find(Query.ElemMatch("Subscriptions", Query.EQ("FeedId", new ObjectId(feed.Id)))).ToList();
            if (!users.Any())
            {
                Pierce.Feeds.Remove(Query.EQ("_id", new ObjectId(feed.Id)));
                return true;
            }
            var interval = users
                .Select(x => x.GetSubscription(feed.Id))
                .Where(x => x != null)
                .Select(x => x.CheckInterval)
                .Min();
            feed.ReadInterval = interval;
            return false;
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

        // The RSS2.0 spec doesn't mandate RFC1123 dates, but it does mention them.
        const string Rfc1123 = "ddd, d MMM yyyy HH':'mm':'ss";
        const int Rfc1123Length = 25;

        bool TryParseRfc1123(string v, ref DateTime date)
        {
            if (v.Length < Rfc1123Length)
                return false;
            DateTime d;
            // Since the length of the date can vary by 1, we might cut off on one side of the final space
            // or the other. We trim both sides to be sure.
            var datePart = v.Substring(0, Rfc1123Length).Trim();
            if (DateTime.TryParseExact(datePart, Rfc1123, null, DateTimeStyles.None, out d))
            {
                try
                {
                    var tzPart = v.Substring(Rfc1123Length).Trim();
                    TimeZoneInfo tz = TimeZoneInfo.FindSystemTimeZoneById(tzPart);
                    d = TimeZoneInfo.ConvertTimeToUtc(d, tz);
                }
                catch
                {
                }
                date = d;
                return true;
            }
            Console.WriteLine("bad date found: {0}", v);
            return false;
        }

        private static readonly XNamespace atom = "http://www.w3.org/2005/Atom";

        public void Read(Feed feed, TextReader feedText)
        {
            var text = feedText.ReadToEnd();
            Console.WriteLine("reading feed {0}", feed.Uri);
            XDocument x = XDocument.Parse(text);
            var rss = x.Descendants("rss").FirstOrDefault();
            XName atomFeedName = atom + "feed";
            var atomFeed = x.Descendants(atomFeedName).FirstOrDefault();
            if (rss == null)
            {
                if (atomFeed == null)
                {
                    throw new ArgumentException("Feed did not contain an <rss> or <feed> element.");
                }
                ReadAtom(feed, x);
            }
            else
            {
                ReadRss(feed, x);
            }
        }
        
        private void Elem(XElement element, XName descendant, params Action<string>[] setter)
        {
            var vs = element.Elements(descendant);
            foreach (var v in vs)
            {
                foreach (var s in setter)
                {
                    try
                    {
                        s(v.Value);
                        return;
                    }
                    catch
                    {
                    }
                }
            }
        }
        
        private void ElemAttrLink(XElement xelem, Action<Uri> setter)
        {
            ElemAttrLink(xelem, null, setter);
        }

        private void ElemAttrLink(XElement xelem, string rel, Action<Uri> setter)
        {
            Uri uri;
            foreach (var name in new XName[]{"link", atom + "link"})
            {
                var selected = xelem.Elements(name);
                foreach (var s in selected)
                {
                    if (rel != null)
                    {
                        if (s.Attribute("rel") != null && s.Attribute("rel").Value != rel)
                        {
                            continue;
                        }
                    }
                    if (s.Attribute("href") == null)
                        continue;
                    if (Uri.TryCreate(s.Attribute("href").Value, UriKind.Absolute, out uri))
                    {
                        setter(uri);
                    }
                }
            }
        }

        private void ElemLink(XElement xelem, XName descendant, Action<Uri> setter)
        {
            var ds = xelem.Elements(descendant);
            foreach (var d in ds)
            {
                Uri uri;
                if (Uri.TryCreate(d.Value, UriKind.Absolute, out uri))
                {
                    setter(uri);
                }
            }
        }

        private void ReadAuthors(XElement entry, string name, ICollection<Author> output)
        {
            foreach (var xauthor in entry.Elements(atom + name))
            {
                var author = new Author();
                Elem(xauthor, atom + "name", v => author.Name = v);
                ElemLink(xauthor, atom + "uri", v => author.Link = v);
                Elem(xauthor, atom + "email", v => author.Email = v);
                if (!output.Where(x => x.Name == author.Name).Any())
                {
                    output.Add(author);
                }
            }
        }

        private void ReadAtom(Feed feed, XDocument x)
        {
            var xfeed = x.Descendants(atom + "feed").First();
            Elem(xfeed, atom + "title", v => feed.Title = v);
            ElemAttrLink(xfeed, "alternate", v => feed.Link = v);
            ElemLink(xfeed, atom + "icon", v => feed.IconUri = v);
            ElemLink(xfeed, atom + "logo", v => feed.LogoUri = v);
            ReadAuthors(xfeed, "author", feed.Authors);
            ReadAuthors(xfeed, "contributor", feed.Authors);
            foreach (var xentry in xfeed.Elements(atom + "entry"))
            {
                var article = new Article();
                Elem(xentry, atom + "id", v => article.UniqueId = v);
                Elem(xentry, atom + "title", v => article.Title = v);
                ReadAuthors(xentry, "author", article.Authors);
                ReadAuthors(xentry, "contributor", article.Authors);
                ElemAttrLink(xentry, v => article.Link = v);
                // Atom uses ISO8601 rather than RFC1123. Yay!
                Elem(xentry, atom + "published", v => article.PublishDate = DateTime.Parse(v).ToUniversalTime());
                if (article.PublishDate == DateTime.MinValue)
                {
                    Elem(xentry, atom + "updated", v => article.PublishDate = DateTime.Parse(v).ToUniversalTime());
                }
                Elem(xentry, atom + "summary", v => article.Summary = v);

                // Should pay attention to the content type.
                var content = xentry.Elements(atom + "content").FirstOrDefault();
                if (content != null)
                {
                    if (!string.IsNullOrWhiteSpace(content.Value))
                    {
                        article.Description = content.Value;
                    }
                    var attr = content.Attribute("src");
                    if (attr != null)
                    {
                        if (article.Link == null)
                        {
                            // Maybe just have a series of links, with optional tag?
                            Uri.TryCreate(attr.Value, UriKind.Absolute, out article.Link);
                        }
                    }
                }
                if (article.UniqueId == null)
                {
                    article.UniqueId = article.Link.ToString();
                }
                feed.AddArticle(article);
            }
        }

        private void ReadRss(Feed feed, XDocument x)
        {
            var channel = x.Element("rss").Element("channel");
            if (channel == null)
            {
                throw new ArgumentException("Feed did not contain a <channel> element.");
            }
            Elem(channel, "title", v => feed.Title = v);
            Elem(channel, "description", v => feed.Description = v);
            Elem(channel, "link", v => feed.Link = new Uri(v));
            var img = channel.Elements("image").FirstOrDefault();
            if (img != null)
            {
                Elem(img, "title", v => feed.ImageTitle = v);
                ElemLink(img, "url", v => {
                    feed.LogoUri = v;
                    feed.IconUri = v; }
                );
                ElemLink(img, "link", v => feed.ImageLinkTarget = v);
            }
            foreach (var item in channel.Elements("item").AsEnumerable())
            {
                var a = new Article();
                a.PublishDate = DateTime.UtcNow;
                Elem(item, "title", v => a.Title = v);
                Elem(item, "author", v => a.Authors.Add(new Author { Name = v }));
                Elem(item, "description", v => a.Description = v);
                Elem(item, "guid", v => a.UniqueId = v);
                Elem(item, "pubDate", v => a.PublishDate = DateTime.Parse(v), v => TryParseRfc1123(v, ref a.PublishDate));
                ElemLink(item, "link", v => a.Link = v);
                ElemLink(item, "comments", v => a.CommentLink = v);
                
                var existing = feed.GetArticle(a.UniqueId);
                if (existing != null)
                {
                    feed.Articles.Remove(existing);
                    if (!item.Elements("pubDate").Any())
                    {
                        a.PublishDate = existing.PublishDate;
                    }
                }
                if (a.UniqueId == null)
                {
                    a.UniqueId = a.Link.ToString();
                }
                feed.AddArticle(a);
            }
        }
    }
}