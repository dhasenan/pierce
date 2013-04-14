using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using HtmlAgilityPack;
using Castle.Core.Logging;
using System.Xml.Linq;

namespace pierce
{
    public class AutodetectFeeds
    {
        private readonly Wget _wget;
        private readonly FeedParser _parser;
        private readonly ILogger _logger;
        private readonly ReadFeeds _reader;

        public AutodetectFeeds(Wget wget, FeedParser parser, ReadFeeds reader, ILogger logger)
        {
            _wget = wget;
            _parser = parser;
            _reader = reader;
            _logger = logger;
        }

        private Feed ReadRss(Uri pageUrl, HtmlNode link)
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
                    feed.Uri = new Uri(pageUrl, targetAttribute.Value);
                    // Some people in the wild use a "feed" scheme. IANA doesn't recognize this, though.
                    if (feed.Uri.Scheme == "feed")
                    {
                        feed.Uri = new Uri("http" + feed.Uri.ToString().Substring(4));
                    }
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

        private void FindFeeds(HtmlDocument doc, Uri pageUrl, List<Feed> feeds, string type)
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
            Uri uri;
            if (pageUrl.StartsWith("feed://"))
            {
                pageUrl = "http" + pageUrl.Substring(4);
            }
            else if (!pageUrl.StartsWith("http"))
            {
                // We don't support gopher links.
                pageUrl = "http://" + pageUrl;
            }
            uri = new Uri(pageUrl);
            var feeds = new List<Feed>();
            var existing = Feed.ByUri(uri.ToString());
            if (existing != null)
            {
                feeds.Add(existing);
                return feeds;
            }
            string text = _wget.Text(uri);
            if (text == null)
            {
                return feeds;
            }

            // Is this an rss feed or an html page?
            try
            {
                // rss feed definitely shouldn't parse as html
                var doc = new HtmlDocument();
                doc.LoadHtml(text);
                FindFeeds(doc, uri, feeds, "application/rss+xml");
                FindFeeds(doc, uri, feeds, "application/atom+xml");
            }
            catch
            {
            }

            try
            {
                var feed = new Feed();
                feed.Uri = uri;
                var xdoc = XDocument.Parse(text);
                _parser.Read(feed, xdoc);
                // This supercedes the html stuff, on the off chance someone put <link> elements in their feed.
                feeds.Clear();
                feeds.Add(feed);
            }
            catch
            {
            }

            if (feeds.Count == 1 && feeds [0].Articles.Count == 0)
            {
                _reader.Read(feeds [0]);
            }
            return feeds;
        }
    }
}

