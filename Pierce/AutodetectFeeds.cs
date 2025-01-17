using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using HtmlAgilityPack;
using System.Xml.Linq;
using Microsoft.Extensions.Logging;

namespace Pierce;

public class AutodetectFeeds
{
  private readonly Wget _wget;
  private readonly FeedParser _parser;
  private readonly ILogger<AutodetectFeeds> _logger;
  private readonly ReadFeeds _reader;

  public AutodetectFeeds(Wget wget, FeedParser parser, ReadFeeds reader, ILogger<AutodetectFeeds> logger)
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
      Uri uri;
      var targetAttribute = link.Attributes ["href"];
      if (targetAttribute == null)
      {
        return null;
      }
      else
      {
        _logger.LogDebug($"looking for RSS / Atom document at {targetAttribute.Value}");
        uri = new Uri(pageUrl, targetAttribute.Value);
        // Some people in the wild use a "feed" scheme. IANA doesn't recognize this, though.
        if (uri.Scheme == "feed")
        {
          uri = new Uri("http" + uri.ToString().Substring(4));
        }
      }
      var feed = new Feed(uri);
      var titleAttribute = link.Attributes ["title"];
      if (titleAttribute != null)
      {
        feed.Title = titleAttribute.Value;
      }
      else
      {
        _logger.LogDebug($"no page title and no feed found from page at {pageUrl}");
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
    _logger.LogDebug($"feeds from page {pageUrl}: got links {rssLinks}");
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

  public async Task<List<Feed>> FromHtmlPage(string pageUrl)
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
    _logger.LogDebug("looking for feeds at {0}", uri);
    var feeds = new List<Feed>();
    string text = await _wget.Text(uri);
    if (text == null)
    {
      _logger.LogDebug("we failed to find any page at that URL");
      return feeds;
    }

    // Is this an rss feed or an html page?
    try
    {
      // rss feed definitely shouldn't parse as html
      _logger.LogDebug($"trying to load URL {uri} as an HTML document...");
      var doc = new HtmlDocument();
      doc.LoadHtml(text);
      FindFeeds(doc, uri, feeds, "application/rss+xml");
      FindFeeds(doc, uri, feeds, "application/atom+xml");
      _logger.LogDebug("...done, found {0} feeds", feeds.Count);
    }
    catch (Exception ex)
    {
      _logger.LogDebug(ex, "failed to find feed links");
    }

    try
    {
      _logger.LogDebug($"trying to load URL {uri} as a feed document...");
      var feed = new Feed(uri);
      var xdoc = XDocument.Parse(text);
      _parser.Read(feed, xdoc);
      // This supersedes the html stuff, on the off chance
      // that someone put <link> elements in their feed.
      feeds.Clear();
      feeds.Add(feed);
      _logger.LogDebug("...success!");
    }
    catch (Exception ex)
    {
      _logger.LogDebug(ex, "failed to parse the document as an RSS or Atom feed");
    }

    _logger.LogDebug("done searching; found {0} feeds", feeds.Count);

    if (feeds.Count == 1 && feeds[0].Articles.Count == 0)
    {
      var f = feeds[0];
      _reader.Read(f);
    }
    return feeds;
  }
}
