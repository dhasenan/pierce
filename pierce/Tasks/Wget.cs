using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Xml.Linq;
using HtmlAgilityPack;
using Castle.Core.Logging;
using System.Net.Cache;
using System.Net.Http;

namespace pierce
{
	public class Wget
	{
		private readonly ILogger _logger;
		private readonly HttpRequestCachePolicy _policy;
		private HttpClient _http;
		private DateTime _lastRefreshed;

		public Wget(ILogger logger)
		{
			this._logger = logger;
			// We shouldn't normally contact the same feed twice within 30 minutes.
			// In case we do, use cached values.
			this._policy = new HttpRequestCachePolicy(HttpCacheAgeControl.MaxAge, TimeSpan.FromMinutes(10));
			_http = new HttpClient();
			_lastRefreshed = DateTime.UtcNow;
		}

		public string Text(Uri uri)
		{
			return Stream(uri, (str) => str);
		}

		public HtmlDocument Html(Uri uri)
		{
			return Stream(uri, (tr) =>
				{
					var doc = new HtmlDocument();
					doc.LoadHtml(tr);
					return doc;
				});
		}

		public XDocument Xml(Uri uri)
		{
			return Stream(uri, (text) =>
				{
					// I've seen people trying to put a data link escape character in their feeds. Bozhe moi!
					if (text.Any(c => !IsXmlChar(c)))
					{
						text = new string(text.Where(IsXmlChar).ToArray());
					}
					return XDocument.Parse(text);
				});
		}

		private T Stream<T>(Uri uri, Func<string, T> f)
		{
			if (_lastRefreshed < DateTime.UtcNow - TimeSpan.FromMinutes(10))
			{
				_http = new HttpClient();
				_lastRefreshed = DateTime.UtcNow;
			}
			var task = _http.GetStringAsync(uri);
			task.Wait();
			if (task.IsFaulted)
			{
				_logger.InfoFormat(task.Exception, "failed to get response from URL {0}");
			}
			return f(task.Result);
		}

		private bool IsXmlChar(char c)
		{
			// Implementing this ourselves because mono hasn't.
			if (c == 0x9 || c == 0xa || c == 0xd)
				return true;
			if (c >= 0x0020 && c <= 0xd7ff)
				return true;
			if (c >= 0xe000 && c <= 0xfffd)
				return true;
			return false;
		}
	}
}

