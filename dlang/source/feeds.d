module pierce.feeds;

import std.stdio;

import std.algorithm;
import std.array : Appender;
import std.datetime;
import std.experimental.logger;
import std.range : isInputRange;
import std.typecons : Nullable;
import std.uuid;

import arsd.dom;
import vibe.core.log;

import pierce.datetimeformat;
import pierce.domain;
import pierce.opt;
import url;

/**
  * Find the feeds available at the given URL.
  *
  * If the URL points to a feed directly, yield just it.
  * If it points to a web page, return the <link>'d feeds.
  *
  * This doesn't read the referenced articles.
  */
Feed[] findFeeds(URL url)
{
    auto w = wget(url);
    infof("have page for %s", url);
    if (w.isHTML)
    {
        import std.algorithm;
        import std.array;
        return findReferencedFeedsInHTML(w)
            .map!wget
            .map!findFeed
            .filter!(x => x.present)
            .map!(x => x.get)
            .array;
    }
    auto f = findFeed(w);
    if (f.present) return [f.get];
    return null;
}

Article[] fetchArticles(Feed feed)
{
    import std.algorithm.sorting : sort;
    import etc.linux.memoryerror : NullPointerError;

    auto w = wget(feed.url.parseURL);
    if (w.text.length == 0)
    {
        errorf("got no text from %s", feed.url);
        return null;
    }
    try
    {
        auto articles = parseArticles(feed, w);
        articles.sort!((x, y) => x.publishDate > y.publishDate);
        return articles;
    }
    catch (NullPointerError e)
    {
        errorf("error while reading feed id:%s url:%s: %s\ndocument:\n%s",
                feed.id, feed.url, e, w.text);
        return null;
    }
}

Article[] parseArticles(Feed feed, Page page)
{
    import std.range : chain;
    // We don't know whether this is RSS or Atom.
    // Thanks to XKCD etc, we may never know.
    // So try both.
    auto dom = new Document(page.text, false, true);
    auto container = dom.optionSelector("channel,feed");
    if (container is null)
    {
        warningf("failed to find feed or channel in page for %s", feed.url);
        return null;
    }
    auto elem = container.element;
    return feed.parseArticles(
            chain(
                elem.querySelectorAll("item"),
                elem.querySelectorAll("entry")));
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
        art.readDate = Clock.currTime(UTC());
        art.feedId = feed.id;

        art.internalId = elem.optionSelector("guid,id").innerText;
        art.title = elem.first("title").txt;
        auto link = elem.querySelector("link");
        if (link)
        {
            art.url = link.attrs.get("href");
            if (art.url.length == 0)
            {
                art.url = link.innerText;
            }
        }
        art.description = elem.optionSelector("description,summary").innerText;

        auto authorElem = elem.first("author");
        art.author = authorElem.first("name").or(authorElem).txt;
        if (!art.author)
        {
            Appender!string a;
            bool first = true;
            foreach (author; elem.children)
            {
                if (author.tagName == "author")
                {
                    if (!first) a ~= ", ";
                    first = false;
                    a ~= author.txt;
                }
            }
            art.author = a.data;
        }

        auto datestr = elem.optionSelector("pubDate,updated,published").innerText;
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
Page wget(URL url)
{
    import vibe.http.client;
    import vibe.core.stream : InputStream;
    // TODO rate limiting and caching
    // TODO check what sort of DNS caching is going on
    infof("fetch %s", url);
    Page page;
    try
    {
        page = reqClient(url);
    }
    catch (Exception e)
    {
        errorf("failed to contact %s: %s", url, e);
        throw e;
    }

    // TODO encodings
    return page;
}

private Page reqClient(URL url)
{
    import vibe.http.client;
    Page page;
    auto client = new HTTPClient;
    auto tls = url.scheme == "https";
    ushort defaultPort = tls ? 443 : 80;
    client.connect(url.host, url.port, tls, new HTTPClientSettings);
    client.request(
        (scope HTTPClientRequest req)
        {
            req.method = HTTPMethod.GET;
            req.requestURL = url.path;
            // Provide port number when it is not the default one (RFC2616 section 14.23)
            if (url.port && url.port != defaultPort)
            {
                import std.format : format;
                req.headers["Host"] = format("%s:%d", url.host, url.port);
            }
            else
                req.headers["Host"] = url.host;
        },
        (scope HTTPClientResponse resp)
        {
            if (resp.statusCode >= 300 && resp.statusCode <= 399)
            {
                page = wget(resp.headers["Location"].parseURL);
                return;
            }
            import vibe.stream.operations : readAllUTF8;
            auto data = resp.bodyReader.readAllUTF8();
            page = Page(data, resp.contentType, url, Clock.currTime);
        });
    client.disconnect;
    return page;
}

Nullable!Feed findFeed(Page page)
{
    Nullable!Feed m;
    Document doc;
    try
    {
        doc = new Document(page.text);
    }
    catch (MarkupException e)
    {
        infof("failed to parse document at %s as XML: %s", page.url, e);
        return nothing!Feed;
    }

    // We *should* be able to use the Content-Type header to pare things down.
    // But with the wide variety, we may as well just try both and see what works.
    auto f = parseAtomHeader(doc, page.url);
    if (f.present) return f;
    return parseRSSHeader(doc, page.url);
}

URL[] findReferencedFeedsInHTML(Page p)
{
    URL[] found;
    // TODO encodings
    auto doc = new Document(p.text);
    auto links = doc.querySelectorAll("link");
    foreach (link; links)
    {
        if (link.getAttribute("type").canFind(RSS_CONTENT_TYPE) ||
            link.getAttribute("type").canFind(ATOM_CONTENT_TYPE))
        {
            found ~= p.url.resolve(link.getAttribute("href"));
        }
    }
    return found;
}

enum ATOM_CONTENT_TYPE = "application/atom+xml";
enum RSS_CONTENT_TYPE = "application/rss+xml";
enum XML_CONTENT_TYPE = "text/xml";
enum XML_CONTENT_TYPE_ALT = "application/xml";
enum HTML_CONTENT_TYPE = "text/html";
enum XHTML_CONTENT_TYPE = "application/xhtml+xml";

struct Page
{
    string text;
    string contentType;
    URL url;
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

    bool isXML() @property
    {
        return
            contentType.startsWith(XML_CONTENT_TYPE) ||
            contentType.startsWith(XML_CONTENT_TYPE_ALT);
    }
}

Element first(Element parent, string tag)
{
    // TODO check Atom namespace too
    // (Dunno how std.xml works, doesn't seem to have xmlns thing explicitly)
    if (parent is null) return null;
    if (parent.tagName == tag) return parent;
    return parent.querySelector(tag);
}

string text(Element elem)
{
    if (elem is null) return null;
    return elem.text();
}

Nullable!Feed parseAtomHeader(Document doc, string url)
{
    auto d = doc.root.first("feed");
    if (d is null) return nothing!Feed;
    Feed f;

    f.title = d.first("title").txt;
    f.url = url;
    f.iconURL = d.first("icon").txt;
    return just(f);
}

Nullable!Feed parseRSSHeader(Document doc, string url)
{
    auto channel = doc.root.first("rss").first("channel");
    if (channel is null) nothing!Feed;
    Feed feed;
    feed.title = channel.first("title").txt;
    feed.url = url;
    feed.iconURL = channel.first("image").first("url").txt;
    return just(feed);
}

string txt(Element elem)
{
    import std.string : strip;
    if (elem is null) return "";
    return elem.innerText.strip;
}

string attr(Element elem, string name)
{
    if (elem is null) return null;
    return elem.attrs.get(name);
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
    auto doc = new Document(atom, false, true);
    auto maybeFeed = parseAtomHeader(doc, "localhost/atom");
    assert(maybeFeed.present);
    auto feed = maybeFeed.get;
    assert(feed.title == "Example Feed");
    auto id = randomUUID();
    feed.id = id;

    auto arts = parseArticles(
            feed,
            Page(atom, ATOM_CONTENT_TYPE, "http://localhost/atom".parseURL));
    assert(arts.length == 1);
    auto art = arts[0];
    assert(art.internalId == "urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a", art.internalId);
    assert(art.feedId == id);
    assert(art.title == "Atom-Powered Robots Run Amok");
    assert(art.description == "Some text.", "[" ~ art.description ~ "]");
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
    auto maybeFeed = parseRSSHeader(new Document(rss, false, true), "localhost/rss");
    auto feed = maybeFeed.get;
    assert(feed.title == "RSS Title");
    auto id = randomUUID();
    feed.id = id;

    auto arts = parseArticles(feed, Page(rss, RSS_CONTENT_TYPE, "http://localhost/rss".parseURL));
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

