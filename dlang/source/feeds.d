module pierce.feeds;

import std.stdio;

import std.algorithm;
import std.array : Appender;
import std.datetime;
import std.range : isInputRange;
import std.typecons : Nullable;
import std.uuid;
static import std.xml;

import arsd.dom;
import vibe.core.log;

import pierce.datetimeformat;
import pierce.domain;
import pierce.opt;

alias XDoc = std.xml.Document;
alias XElem = std.xml.Element;
alias XMLException = std.xml.XMLException;

/**
  * Find the feeds available at the given URL.
  *
  * If the URL points to a feed directly, yield just it.
  * If it points to a web page, return the <link>'d feeds.
  *
  * This doesn't read the referenced articles.
  */
Feed[] findFeeds(string url)
{
    auto w = wget(url);
    if (w.isHTML)
    {
        import std.algorithm;
        import std.array;
        return findReferencedFeedsInHTML(w)
            .map!wget
            .map!findFeed
            .filter!(x => x.present)
            .map!(x => x.value)
            .array;
    }
    auto f = findFeed(w);
    if (f.present) return [f.value];
    return null;
}

Article[] parseArticles(Feed feed, Page page)
{
    auto dom = new XDoc(page.text);
    XElem feedContainer;
    if (page.isRSS)
    {
        feedContainer = dom.first("rss").first("channel");
        return feed.parseArticles(
            dom.first("rss").first("channel")
                .elements
                .filter!(x => x.tag.name == "item"));
    }
    else if (page.isAtom)
    {
        feedContainer = dom.first("feed");
        return feed.parseArticles(
                feedContainer.elements.filter!(x => x.tag.name == "entry"));

    }
    return parseArticles(
            feed,
            feedContainer.elements
                .filter!(x => x.tag.name == "item" || x.tag.name == "entry"));
}

/**
  * Grab articles from a feed.
  */
Article[] parseArticles(TRange)(Feed feed, TRange elems) if (isInputRange!TRange)
{
    Article[] ret;
    foreach (elem; elems)
    {
        Article art;
        art.feedId = feed.id;

        art.internalId = elem.first("guid").txt
            .or(elem.first("id").txt);
        art.title = elem.first("title").txt;
        art.url = elem.first("link").txt
            .or(elem.first("link").attr("href"));
        art.description = elem.first("description").txt
            .or(elem.first("summary").txt);

        art.author = elem.first("author").txt;
        if (!art.author)
        {
            Appender!string a;
            bool first = true;
            foreach (author; elem.elements)
            {
                if (author.tag.name == "author")
                {
                    if (!first) a ~= ", ";
                    first = false;
                    a ~= author.txt;
                }
            }
            art.author = a.data;
        }

        auto datestr = elem.first("pubDate").txt
            .or(elem.first("updated").txt)
            .or(elem.first("published").txt);
        SysTime st;
        if (datestr != "")
        {
            if (tryParse(datestr, RFC1123FORMAT, st, UTC()))
            {
                art.publishDate = st;
            }
            else if (tryParse(datestr, ISO8601FORMAT, st, UTC()))
            {
                art.publishDate = st;
            }
        }
        ret ~= art;
    }
    return ret;
}

/**
  * Download the page at the given URL.
  */
Page wget(string url)
{
    import vibe.http.client;
    import vibe.core.stream : InputStream;
    auto limit = Clock.currTime - dur!"minutes"(15);
    foreach (k, v; downloadCache)
    {
        auto f = cast(immutable)v.downloaded;
        if (f < limit)
        {
            downloadCache.remove(k);
        }
    }
    if (auto existing = url in downloadCache)
    {
        return *existing;
    }
    auto resp = requestHTTP(url);
    Appender!(ubyte[]) a;
    resp.readRawBody(delegate void (scope InputStream stream) scope {
        while (!stream.empty)
        {
            auto buf = new ubyte[stream.leastSize];
            stream.read(buf);
            a ~= buf;
        }
    });

    // TODO encodings
    return Page(cast(string)a.data, resp.contentType, url, Clock.currTime);
}

shared Page[string] downloadCache;

Maybe!Feed findFeed(Page page)
{
    Maybe!Feed m;
    XDoc doc;
    try
    {
        doc = new XDoc(page.text);
    }
    catch (XMLException e)
    {
        logInfo("failed to parse document at %s as XML: %s", page.url, e);
        return nothing!Feed;
    }

    if (page.isAtom)
    {
        return parseAtomHeader(doc, page.url);
    }
    else if (page.isRSS)
    {
        return parseRSSHeader(doc, page.url);
    }

    logInfo("page at %s has unrecognized content type %s", page.url, page.contentType);
    return nothing!Feed;
}

string[] findReferencedFeedsInHTML(Page p)
{
    string[] found;
    // TODO encodings
    auto doc = new Document(p.text);
    auto links = doc.querySelectorAll("link");
    foreach (link; links)
    {
        if (link.getAttribute("type").canFind(RSS_CONTENT_TYPE) ||
            link.getAttribute("type").canFind(ATOM_CONTENT_TYPE))
        {
            found ~= link.getAttribute("href");
        }
    }
    return found;
}

enum ATOM_CONTENT_TYPE = "application/atom+xml";
enum RSS_CONTENT_TYPE = "application/rss+xml";
enum HTML_CONTENT_TYPE = "text/html";
enum XHTML_CONTENT_TYPE = "application/xhtml+xml";

struct Page
{
    string text;
    string contentType;
    string url;
    SysTime downloaded;

    bool isHTML() @property
    {
        return contentType.startsWith(HTML_CONTENT_TYPE)
            || contentType.startsWith(XHTML_CONTENT_TYPE);
    }

    bool isAtom() @property
    {
        return contentType.startsWith(ATOM_CONTENT_TYPE);
    }

    bool isRSS() @property
    {
        return contentType.startsWith(RSS_CONTENT_TYPE);
    }
}

XElem first(XElem parent, string tag)
{
    // TODO check Atom namespace too
    // (Dunno how std.xml works, doesn't seem to have xmlns thing explicitly)
    if (parent is null) return null;
    if (parent.tag.name == tag) return parent;
    foreach (e; parent.elements)
    {
        if (e.tag.name == tag)
        {
            return e;
        }
    }
    return null;
}

string text(XElem elem)
{
    if (elem is null) return null;
    return elem.text();
}

Maybe!Feed parseAtomHeader(XDoc doc, string url)
{
    auto d = doc.first("feed");
    if (d is null) return nothing!Feed;
    Feed f;

    f.title = d.first("title").txt;
    f.url = url;
    f.iconURL = d.first("icon").txt;
    return just(f);
}

Maybe!Feed parseRSSHeader(XDoc doc, string url)
{
    auto channel = doc.first("rss").first("channel");
    if (channel is null) nothing!Feed;
    Feed feed;
    feed.title = channel.first("title").txt;
    feed.url = url;
    feed.iconURL = channel.first("image").first("url").txt;
    return just(feed);
}

string txt(XElem elem)
{
    if (elem is null) return null;
    return elem.text;
}

string attr(XElem elem, string name)
{
    if (elem is null) return null;
    auto p = name in elem.tag.attr;
    if (p) return *p;
    return null;
}

T or(T)(T a, T b)
{
    if (!a) return b;
    return a;
}

unittest
{
    enum atom = `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">

  <title>Example Feed</title>
  <link href="http://example.org/"/>
  <updated>2003-12-13T18:30:02Z</updated>
  <author>
    <name>John Doe</name>
  </author>
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>

  <entry>
    <title>Atom-Powered Robots Run Amok</title>
    <link href="http://example.org/2003/12/13/atom03"/>
    <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
    <updated>2003-12-13T18:30:02Z</updated>
    <summary>Some text.</summary>
  </entry>

</feed>`;
    auto doc = new XDoc(atom);
    auto maybeFeed = parseAtomHeader(doc, "localhost/atom");
    assert(maybeFeed.present);
    auto feed = maybeFeed.value;
    assert(feed.title == "Example Feed");
    auto id = randomUUID();
    feed.id = id;

    auto arts = parseArticles(feed, Page(atom, ATOM_CONTENT_TYPE, "localhost/atom"));
    assert(arts.length == 1);
    auto art = arts[0];
    assert(art.internalId == "urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a");
    assert(art.feedId == id);
    assert(art.title == "Atom-Powered Robots Run Amok");
    assert(art.description == "Some text.");
    assert(art.publishDate == SysTime(DateTime(2003, 12, 13, 18, 30, 2), UTC()),
            art.publishDate.toISOString());
    assert(art.url == "http://example.org/2003/12/13/atom03", art.url);
}


unittest
{
    auto rss = `<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">
<channel>
 <title>RSS Title</title>
 <description>This is an example of an RSS feed</description>
 <link>http://www.example.com/main.html</link>
 <lastBuildDate>Mon, 06 Sep 2010 00:01:00 +0000 </lastBuildDate>
 <pubDate>Sun, 06 Sep 2009 16:20:00 +0000</pubDate>
 <ttl>1800</ttl>

 <item>
  <title>Example entry</title>
  <description>Here is some text containing an interesting description.</description>
  <link>http://www.example.com/blog/post/1</link>
  <guid isPermaLink="true">7bd204c6-1655-4c27-aeee-53f933c5395f</guid>
  <pubDate>Sun, 06 Sep 2009 16:20:00 +0000</pubDate>
 </item>

</channel>
</rss>`;
    auto maybeFeed = parseRSSHeader(new XDoc(rss), "localhost/rss");
    auto feed = maybeFeed.value;
    assert(feed.title == "RSS Title");
    auto id = randomUUID();
    feed.id = id;

    auto arts = parseArticles(feed, Page(rss, RSS_CONTENT_TYPE, "localhost/rss"));
    assert(arts.length == 1);
    auto art = arts[0];
    assert(art.internalId == "7bd204c6-1655-4c27-aeee-53f933c5395f");
    assert(art.feedId == id);
    assert(art.title == "Example entry");
    assert(art.description == "Here is some text containing an interesting description.");
    assert(art.publishDate == SysTime(DateTime(2009, 9, 6, 16, 20, 0), UTC()),
            art.publishDate.toISOString());
    assert(art.url == "http://www.example.com/blog/post/1", art.url);
}
