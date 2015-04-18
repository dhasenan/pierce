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
        private readonly Mongo _db;

        public AutodetectFeeds(Wget wget, FeedParser parser, ReadFeeds reader, Mongo db, ILogger logger)
        {
            _wget = wget;
            _parser = parser;
            _reader = reader;
            _db = db;
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
					_logger.InfoFormat("looking for RSS / Atom document at {0}", targetAttribute.Value);
                    feed.Uri = new Uri(pageUrl, targetAttribute.Value);
                    // Some people in the wild use a "feed" scheme. IANA doesn't recognize this, though.
                    if (feed.Uri.Scheme == "feed")
                    {
                        feed.Uri = new Uri("http" + feed.Uri.ToString().Substring(4));
                    }
                    var existing = Feed.ByUri(feed.Uri.ToString(), _db);
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
					_logger.InfoFormat("no page title and no feed found from page at {0}", pageUrl);
                    feed.Title = pageUrl.Host;
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
			_logger.InfoFormat("feeds from page {0}: got links {1}", pageUrl, rssLinks);
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
			_logger.InfoFormat("looking for feeds at {0}", uri);
            var feeds = new List<Feed>();
            var existing = Feed.ByUri(uri.ToString(), _db);
            if (existing != null)
            {
				_logger.Info("we already had that feed!");
                feeds.Add(existing);
                return feeds;
            }
            string text = _wget.Text(uri);
            if (text == null)
            {
				_logger.InfoFormat("we failed to find any page at that URL");
                return feeds;
            }

            // Is this an rss feed or an html page?
            try
            {
                // rss feed definitely shouldn't parse as html
				_logger.InfoFormat("trying to load the URL as an HTML document...");
                var doc = new HtmlDocument();
                doc.LoadHtml(text);
                FindFeeds(doc, uri, feeds, "application/rss+xml");
                FindFeeds(doc, uri, feeds, "application/atom+xml");
				_logger.InfoFormat("...done, found {0} feeds", feeds.Count);
            }
            catch (Exception ex)
            {
				_logger.InfoFormat(ex, "failed to find feed links");
            }

            try
            {
				_logger.InfoFormat("trying to load the URL as a feed document...");
                var feed = new Feed();
                feed.Uri = uri;
                var xdoc = XDocument.Parse(text);
                _parser.Read(feed, xdoc);
                // This supercedes the html stuff, on the off chance someone put <link> elements in their feed.
                feeds.Clear();
                feeds.Add(feed);
				_logger.InfoFormat("...success!");
            }
            catch (Exception ex)
            {
				_logger.InfoFormat(ex, "failed to parse the document as an RSS or Atom feed");
            }

			_logger.InfoFormat("done searching; found {0} feeds", feeds.Count);

            if (feeds.Count == 1 && feeds [0].Articles.Count == 0)
            {
                var f = feeds [0];
                _reader.Read(f);
                f.Save(_db);
            }
            return feeds;
        }
    }
}

