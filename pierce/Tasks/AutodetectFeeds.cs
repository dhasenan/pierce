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

            // Is this an rss feed or an html page?
            try
            {
                var doc = new HtmlDocument();
                doc.LoadHtml(text);
                var rssLinks = doc.DocumentNode.SelectNodes("//link[@type='application/rss+xml']");
                if (rssLinks == null)
                    return feeds;
                foreach (var link in rssLinks)
                {
                    try
                    {
                        var feed = new Feed();
                        var targetAttribute = link.Attributes ["href"];
                        if (targetAttribute == null)
                        {
                            continue;
                        }
                        else
                        {
                            feed.Uri = new Uri(new Uri(pageUrl), targetAttribute.Value);
                            existing = Feed.ByUri(feed.Uri.ToString());
                            if (existing != null)
                            {
                                feeds.Add(existing);
                                continue;
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
                        feeds.Add(feed);
                    }
                    catch
                    {
                        // Malformed thingy; maybe there's a better one later.
                    }
                }
            }
            catch
            {
                var feed = new Feed();
                feed.Uri = new Uri(pageUrl);
                new ReadFeeds().Read(feed, new StringReader(text));
                feeds.Add(feed);
            }
            return feeds;
        }
    }
}

