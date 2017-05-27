module pierce.feeds;

import std.typecons : Nullable;
import std.xml;

import datefmt;
import vibe.d;

alias XDoc = std.xml.Document;
alias XElem = std.xml.XElement;

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
                .filter!(x => x.tag == "item"));
    }
    else if (page.isAtom)
    {
        feedContainer = dom.first("feed");
        return feed.parseArticles(
            dom.first("").first("channel")
                .elements
                .filter!(x => x.tag == "item"));

    }
    return parseArticles(
            feed,
            feedContainer.elements
                .filter!(x => x.tag == "item" || x.tag == "entry"));
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
        art.url = elem.first("link").txt;
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
            if (tryParse(datestr, RFC1123FORMAT, out st))
            {
                art.publishDate = st;
            }
            else if (tryParse(datestr, ISO8601FORMAT, out st))
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
    auto limit = Clock.currTime - dur!"minutes"(15);
    foreach (k, v; downloadCache)
    {
        if (v.downloaded < limit)
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
    resp.readRawBody((stream) {
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

Maybe!Feed findFeed(Page w)
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

    if (w.isAtom)
    {
        return parseAtomHeader(doc, w.url);
    }
    else if (w.isRSS)
    {
        return parseRSSHeader(doc, w.url);
    }

    logInfo("page at %s has unrecognized content type %s", url, w.contentType);
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
        else if ()
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

T or(T)(T a, T b)
{
    if (!a) return b;
    return a;
}

unittest
{
    
}
