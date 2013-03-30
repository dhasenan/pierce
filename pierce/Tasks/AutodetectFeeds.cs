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
            WebRequest wr = WebRequest.Create(pageUrl);
            wr.Method = "GET";
            TextReader reader = new StreamReader(wr.GetResponse().GetResponseStream());
            var text = reader.ReadToEnd();
            reader = new StringReader(text);
            var feeds = new List<Feed>();
            // Is this an rss feed or an html page?
            // Try rss first.
            try
            {
                var feed = new Feed();
                new ReadFeeds().Read(feed, reader);
                feeds.Add(feed);
            }
            catch
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
                        var titleAttribute = link.Attributes ["title"];
                        if (titleAttribute != null)
                        {
                            feed.Title = titleAttribute.Value;
                        }
                        else
                        {
                            feed.Title = "RSS";
                        }
                        var targetAttribute = link.Attributes ["href"];
                        if (targetAttribute == null)
                        {
                            continue;
                        }
                        else
                        {
                            feed.Uri = new Uri(new Uri(pageUrl), targetAttribute.Value);
                        }
                        feeds.Add(feed);
                    }
                    catch
                    {
                        // Malformed thingy; maybe there's a better one later.
                    }
                }

            }
            return feeds;
        }
    }
}

