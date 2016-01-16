using NUnit.Framework;
using System;
using Castle.Core.Logging;
using System.Xml.Linq;
using System.IO;
using System.Linq;

namespace pierce.test
{
    [TestFixture()]
    public class SomethingPositiveTest
    {
        string feed = @"<?xml version=""1.0""?>
                <rss version=""2.0"">
                    <channel>
                        <title>Something Positive by R.K. Milholland</title>
            <link>http://www.somethingpositive.net</link>
                        <description>Comics strips, news updates, and convention schedule for the webcomic Something Positive.</description>
                        <copyright>(c) 2001-2016 R.K. Milholland</copyright>
            <managingEditor>choochoobear@gmail.com</managingEditor>
                        <lastBuildDate>Mon, Jan 11 2016 05:30:00 GMT</lastBuildDate>
                        <item>
                            <title>Old Familiar Faces XIV pt 1</title>
                            <link>http://www.somethingpositive.net/sp01112016.shtml</link>
                            <description>Also, a blog post.
                            </description>
                        </item>
                        <item>
                            <title>Next Week</title>
                            <link>http://www.somethingpositive.net/sp01072016.shtml</link>
                            <description>
                            </description>
                        </item>
                        <item>
                            <title>Clarine's Birthday</title>
                            <link>http://www.somethingpositive.net/sp01052016.shtml</link>
                            <description>
                            </description>
                        </item>
                        <item>
                            <title>Unfinished Watercolors</title>
                            <link>http://www.somethingpositive.net/sp01042016.shtml</link>
                            <description>
                            </description>
                        </item>
                        <item>
                            <title>Rejected Suggestions</title>
                            <link>http://www.somethingpositive.net/sp01012016.shtml</link>
                            <description>
                            </description>
                        </item>
                    </channel>
                </rss>
";
        [Test()]
        public void TestCase()
        {
            var feed = new Feed();
            feed.Head = new Chunk();
            var target = new FeedParser(null, NullLogger.Instance);
            XDocument doc = XDocument.Load(new StringReader(this.feed));
            target.Read(feed, doc);
            Assert.That(feed.GetHeadChunk(null).Articles.Count, Is.EqualTo(5));
        }

        [Test]
        public void HashTest() {
            XDocument doc1 = XDocument.Load(new StringReader(this.feed));
            XDocument doc2 = XDocument.Load(new StringReader(this.feed));
            XElement elem1 = doc1.Descendants("item").First();
            XElement elem2 = doc2.Descendants("item").First();
            XElement elem3 = doc2.Descendants("item").Skip(1).First();
            Console.WriteLine(elem3.ToString());
            Assert.That(elem1.ToString().GetHashCode(), Is.EqualTo(elem2.ToString().GetHashCode()));
            Assert.That(elem1.ToString().GetHashCode(), Is.Not.EqualTo(elem3.ToString().GetHashCode()));
        }
    }
}

