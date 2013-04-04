using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using HtmlAgilityPack;

namespace pierce
{
    public class AutodetectFeeds
    {
        private Feed ReadRss(string pageUrl, HtmlNode link)
        {
            try
            {
                var feed = new Feed();
                var targetAttribute = link.Attributes ["href"];
                if (targetAttribute == null)
                {
                    return null;
                }
                else
                {
                    feed.Uri = new Uri(new Uri(pageUrl), targetAttribute.Value);
                    var existing = Feed.ByUri(feed.Uri.ToString());
                    if (existing != null)
                    {
                        return existing;
                    }
                }
                var titleAttribute = link.Attributes ["title"];
                if (titleAttribute != null)
                {
                    feed.Title = titleAttribute.Value;
                }
                else
                {
                    feed.Title = "RSS";
                }
                return feed;
            }
            catch
            {
                // malformed
                return null;
            }
        }

        private Uri FindShortcutIcon(HtmlDocument doc, string pageUrl)
        {
            var iconLink = doc.DocumentNode.SelectNodes("//link[@rel='shortcut icon'").FirstOrDefault();
            if (iconLink == null)
                return null;
            Uri uri;
            if (Uri.TryCreate(new Uri(pageUrl), iconLink.GetAttributeValue("href", "favicon.ico"), out uri))
            {
                return uri;
            }
            return null;
        }

        private void FindFeeds(HtmlDocument doc, string pageUrl, List<Feed> feeds, string type)
        {
            var rssLinks = doc.DocumentNode.SelectNodes(string.Format("//link[@type='{0}']", type));
            if (rssLinks != null)
            {
                foreach (var link in rssLinks)
                {
                    var feed = ReadRss(pageUrl, link);
                    if (feed != null)
                    {
                        feeds.Add(feed);
                    }
                }
            }
        }

        public List<Feed> FromHtmlPage(string pageUrl)
        {
            string text;
            var feeds = new List<Feed>();
            var existing = Feed.ByUri(pageUrl);
            if (existing != null)
            {
                feeds.Add(existing);
                return feeds;
            }
            try
            {
                WebRequest wr = WebRequest.Create(pageUrl);
                wr.Method = "GET";
                TextReader tr = new StreamReader(wr.GetResponse().GetResponseStream());
                text = tr.ReadToEnd();
            }
            catch
            {
                // invalid url
                return feeds;
            }

            Uri defaultIcon = null;

            // Is this an rss feed or an html page?
            try
            {
                // rss feed definitely shouldn't parse as html
                var doc = new HtmlDocument();
                doc.LoadHtml(text);
                FindFeeds(doc, pageUrl, feeds, "application/rss+xml");
                FindFeeds(doc, pageUrl, feeds, "application/atom+xml");
                defaultIcon = FindShortcutIcon(doc, pageUrl);
            }
            catch
            {
            }
            try
            {
                // my parsing is lax enough that it might parse some
                // invalid xhtml as an rss feed, maybe
                var feed = new Feed();
                feed.Uri = new Uri(pageUrl);
                new ReadFeeds().Read(feed, new StringReader(text));
                // This supercedes the html stuff.
                feeds.Clear();
                feeds.Add(feed);
            }
            catch
            {
            }

            foreach (var feed in feeds)
            {
                if (feed.IconUri == null)
                {
                    feed.IconUri = defaultIcon;
                }
            }

            if (feeds.Count == 1 && feeds [0].Articles.Count == 0)
            {
                new ReadFeeds().Read(feeds [0]);
            }
            return feeds;
        }
    }
}

