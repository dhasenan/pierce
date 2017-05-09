using System;
using NUnit.Framework;

namespace pierce.test
{
	[TestFixture]
	public class WgetTest
	{
		[Test]
		public void GetFeedburner ()
		{
			string val = new Wget (new MyLoggerFactory ().Create ("default")).Text (new Uri ("http://example.org"));
			Console.WriteLine (val);
		}
	}
}

