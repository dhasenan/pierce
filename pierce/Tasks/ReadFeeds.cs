using System;
using System.Linq;
using System.Collections.Generic;
using System.Net;
using System.IO;
using System.Xml;
using System.Xml.Linq;
using MongoDB.Driver.Builders;

namespace pierce
{
    // TODO(dhasenan): Atom feeds; RSS1.0
    public class ReadFeeds
    {
        public void Execute()
        {
            var list = Pierce.Feeds.Find(Query.LT("NextRead", DateTime.UtcNow));
            Console.WriteLine(list.Count());
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
                    Console.WriteLine(ex);
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
        
        private void Elem(XElement element, string descendant, Action<string> setter)
        {
            var v = element.Descendants(descendant).FirstOrDefault();
            if (v == null)
                return;
            try
            {
                setter(v.Value);
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex);
            }
        }

        public void Read(Feed feed, TextReader feedText)
        {
            XElement x = XElement.Parse(feedText.ReadToEnd());
            var channel = x.Descendants("channel").FirstOrDefault();
            if (channel != null)
            {
                Elem(channel, "title", v => feed.Title = v);
                Elem(channel, "description", v => feed.Description = v);
                Elem(channel, "link", v => feed.Uri = new Uri(v));
                var img = channel.Descendants("image").FirstOrDefault();
                if (img != null)
                {
                    Elem(img, "title", v => feed.ImageTitle = v);
                    Elem(img, "url", v => feed.ImageUri = new Uri(v));
                    Elem(img, "link", v => feed.ImageLinkTarget = new Uri(v));
                }
            }
            foreach (var item in channel.Descendants("item").AsEnumerable())
            {
                var a = new Article();
                a.PublishDate = DateTime.UtcNow;
                Elem(item, "title", v => a.Title = v);
                Elem(item, "author", v => a.Author = v);
                Elem(item, "description", v => a.Description = v);
                Elem(item, "guid", v => a.UniqueId = v);
                Elem(item, "pubDate", v => a.PublishDate = DateTime.Parse(v));
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
                feed.Articles.Add(a);
            }
        }
    }
}