using System;
using NUnit.Framework;
using System.IO;
using System.Linq;
using System.Xml.Linq;

namespace pierce.test
{
    [TestFixture]
    public class ReadFeedsTest
    {
        [Test]
        public void TestCase()
        {
            XNamespace ns = "http://www.w3.org/2005/Atom";
            Console.WriteLine(new XElement(ns + "feed", "content"));
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
                "    <updated>2003-12-13T18:30:02Z</updated>" +
                "    <summary>Some text.</summary>" +
                "  </entry>" +
                "</feed>";
            var feed = new Feed();
            new ReadFeeds().Read(feed, new StringReader(feedXml));
            Assert.That(feed.Articles.Count, Is.EqualTo(1));
            var art = feed.Articles.First();
            Assert.That(art.Title, Is.EqualTo("Atom-Powered Robots Run Amok"));
            Assert.That(art.Link, Is.EqualTo(new Uri("http://example.org/2003/12/13/atom03")));
        }
    }
}

