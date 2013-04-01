using System;
using NUnit.Framework;
using System.IO;
using System.Linq;

namespace pierce.test
{
    [TestFixture]
    public class ReadRssTest
    {
        [Test]
        public void FeedData()
        {
            var feedText = "<?xml version=\"1.0\" ?>" +
                "<rss version=\"2.0\">" +
                "  <channel>" +
                "    <title>StrongBad!!!1</title>" +
                "    <description>Kangaroo Jack's colby jack</description>" +
                "    <webMaster>strongbad@example.org</webMaster>" +
                "    <image>" +
                "      <url>http://strongbad.example.org/content/sb.png</url>" +
                "      <title>Link master</title>" +
                "      <link>http://miku.vocaloid.ru/waffle</link>" +
                "    </image>" +
                "    <link>http://strongbad.example.org/feed</link>" +
                "  </channel>" +
                "</rss>";
            var feed = new Feed();
            new ReadFeeds().Read(feed, new StringReader(feedText));
            Assert.That(feed.Title, Is.EqualTo("StrongBad!!!1"));
            Assert.That(feed.Description, Is.EqualTo("Kangaroo Jack's colby jack"));
            Assert.That(feed.LogoUri, Is.EqualTo(new Uri("http://strongbad.example.org/content/sb.png")));
            Assert.That(feed.ImageLinkTarget, Is.EqualTo(new Uri("http://miku.vocaloid.ru/waffle")));
            Assert.That(feed.ImageTitle, Is.EqualTo("Link master"));
            Assert.That(feed.Link, Is.EqualTo(new Uri("http://strongbad.example.org/feed")));
        }

        [Test]
        public void Article()
        {
            var feedText = "<?xml version=\"1.0\" ?>" +
                "<rss version=\"2.0\">" +
                "  <channel>" +
                "    <title>StrongBad!!!1</title>" +
                "    <description>Kangaroo Jack's colby jack</description>" +
                "    <link>http://strongbad.example.org/feed</link>" +
                "    <item>" +
                "      <title>Incredipede</title>" +
                "      <description>This is a multiline sequence possibly containing HTML.</description>" +
                "      <link>https://dignitas.com/team/tamewymild</link>" +
                "      <author>Team Dignitas</author>" +
                "      <pubDate>Sun, 19 May 2002 15:21:36 GMT</pubDate>" +
                "    </item>" +
                "  </channel>" +
                "</rss>";
            var feed = new Feed();
            new ReadFeeds().Read(feed, new StringReader(feedText));
            var article = feed.Articles.First();
            Assert.That(article.Title, Is.EqualTo("Incredipede"));
            Assert.That(article.Description, Is.EqualTo("This is a multiline sequence possibly containing HTML."));
            Assert.That(article.Link, Is.EqualTo(new Uri("https://dignitas.com/team/tamewymild")));
            Assert.That(article.Authors.Count, Is.EqualTo(1));
            Assert.That(article.Authors.First().Name, Is.EqualTo("Team Dignitas"));
            Assert.That(article.PublishDate, Is.EqualTo(new DateTime(2002, 5, 19, 15, 21, 36)));
        }
    }
}