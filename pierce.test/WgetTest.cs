using System;
using Castle.Core.Logging;
using NUnit.Framework;

namespace pierce.test
{
	public class WgetTest
	{
		[Test]
		public void GetFeedburner ()
		{
			var val = new Wget (new MyLoggerFactory ().Create ("default")).Text (new Uri ("http://feeds.feedburner.com/wondermark"));
			Console.WriteLine (val);
		}
	}
}

