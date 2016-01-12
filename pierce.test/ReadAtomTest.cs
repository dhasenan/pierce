using System;
using NUnit.Framework;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using Castle.Core.Logging;

namespace pierce.test
{
    [TestFixture]
    public class ReadAtomTest
    {
        FeedParser _target;

        [SetUp]
        public void Setup()
        {
            _target = new FeedParser(null, NullLogger.Instance);
        }

        [Test]
        public void ReadFeedData()
        {
            var feedXml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
                "<feed xmlns=\"http://www.w3.org/2005/Atom\">" +
                "  <title>Example Feed</title>" +
                "  <icon>http://example.org/feed/icon.png</icon>" +
                "  <logo>http://example.org/feed/logo.png</logo>" +
                "  <link href=\"http://example.org/\"/>" +
                "  <updated>2003-12-13T18:30:02Z</updated>" +
                "  <author>" +
                "    <name>John Doe</name>" +
                "    <uri>http://fuzzybunnies.example.org/</uri>" +
                "    <email>strongbad@example.org</email>" +
                "  </author>" +
                "  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>" +
                "</feed>";
            var feed = new Feed();
            _target.Read(feed, XDocument.Parse(feedXml));
            Assert.That(feed.Title, Is.EqualTo("Example Feed"));
            Assert.That(feed.Link, Is.EqualTo(new Uri("http://example.org")));
            Assert.That(feed.IconUri, Is.EqualTo(new Uri("http://example.org/feed/icon.png")));
            Assert.That(feed.LogoUri, Is.EqualTo(new Uri("http://example.org/feed/logo.png")));
            var author = feed.Authors.First();
            Assert.That(author.Name, Is.EqualTo("John Doe"));
            Assert.That(author.Email, Is.EqualTo("strongbad@example.org"));
            Assert.That(author.Link, Is.EqualTo(new Uri("http://fuzzybunnies.example.org")));
        }

        [Test]
        public void ReadArticles()
        {
            var feedXml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
                "<feed xmlns=\"http://www.w3.org/2005/Atom\">" +
                "  <title>Example Feed</title>" +
                "  <link href=\"http://example.org/\"/>" +
                "  <updated>2003-12-13T18:30:02Z</updated>" +
                "  <author>" +
                "    <name>John Doe</name>" +
                "  </author>" +
                "  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>" +
                "  <entry>" +
                "    <title>Atom-Powered Robots Run Amok</title>" +
                "    <link href=\"http://example.org/2003/12/13/atom03\"/>" +
                "    <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>" +
                "    <published>2003-12-13T18:30:02Z</published>" +
                "    <updated>2004-01-13T18:30:02Z</updated>" +
                "    <summary>Some text.</summary>" +
                "  </entry>" +
                "</feed>";
            var feed = new Feed();
            _target.Read(feed, XDocument.Parse(feedXml));
            Assert.That(feed.GetHeadChunk(null).Articles.Count, Is.EqualTo(1));
            var art = feed.GetHeadChunk(null).Articles.First();
            Assert.That(art.Title, Is.EqualTo("Atom-Powered Robots Run Amok"));
            Assert.That(art.Link, Is.EqualTo(new Uri("http://example.org/2003/12/13/atom03")));
            Assert.That(art.PublishDate, Is.EqualTo(new DateTime(2003, 12, 13, 18, 30, 2)));
            Assert.That(art.Summary, Is.EqualTo("Some text."));
            Assert.That(art.UniqueId, Is.EqualTo("urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a"));
        }

        [Test]
        public void ReadArticlesTwice()
        {
            var feedXml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
                "<feed xmlns=\"http://www.w3.org/2005/Atom\">" +
                "  <title>Example Feed</title>" +
                "  <link href=\"http://example.org/\"/>" +
                "  <updated>2003-12-13T18:30:02Z</updated>" +
                "  <author>" +
                "    <name>John Doe</name>" +
                "  </author>" +
                "  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>" +
                "  <entry>" +
                "    <title>Atom-Powered Robots Run Amok</title>" +
                "    <link href=\"http://example.org/2003/12/13/atom03\"/>" +
                "    <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>" +
                "    <published>2003-12-13T18:30:02Z</published>" +
                "    <updated>2004-01-13T18:30:02Z</updated>" +
                "    <summary>Some text.</summary>" +
                "  </entry>" +
                "</feed>";
            var feed = new Feed();
            _target.Read(feed, XDocument.Parse(feedXml));
            _target.Read(feed, XDocument.Parse(feedXml));
            Assert.That(feed.GetHeadChunk(null).Articles.Count, Is.EqualTo(1));
        }

        [Test]
        public void NoPublishedOnlyUpdated()
        {
            var feedXml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
                "<feed xmlns=\"http://www.w3.org/2005/Atom\">" +
                "  <title>Example Feed</title>" +
                "  <link href=\"http://example.org/\"/>" +
                "  <updated>2003-12-13T18:30:02Z</updated>" +
                "  <author>" +
                "    <name>John Doe</name>" +
                "  </author>" +
                "  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>" +
                "  <entry>" +
                "    <title>Atom-Powered Robots Run Amok</title>" +
                "    <link href=\"http://example.org/2003/12/13/atom03\"/>" +
                "    <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>" +
                "    <updated>2004-01-13T18:30:02Z</updated>" +
                "    <summary>Some text.</summary>" +
                "  </entry>" +
                "</feed>";
            var feed = new Feed();
            _target.Read(feed, XDocument.Parse(feedXml));
            var art = feed.GetHeadChunk(null).Articles.First();
            Assert.That(art.PublishDate, Is.EqualTo(new DateTime(2004, 1, 13, 18, 30, 2)));
        }
    }
}

