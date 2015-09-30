using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Xml.Linq;
using HtmlAgilityPack;
using Castle.Core.Logging;

namespace pierce
{
	public class Wget
	{
		private readonly ILogger _logger;

		public Wget(ILogger _logger)
		{
			this._logger = _logger;
		}

		public string Text(Uri uri)
		{
			return Stream(uri, (str) =>
				{
					if (str == null)
					{
						return null;
					}
					return str.ReadToEnd();
				});
		}

		public HtmlDocument Html(Uri uri)
		{
			return Stream(uri, (tr) =>
				{
					if (tr == null)
						return null;
					var text = tr.ReadToEnd();
					var doc = new HtmlDocument();
					doc.LoadHtml(text);
					return doc;
				});
		}

		public XDocument Xml(Uri uri)
		{
			return Stream(uri, (tr) =>
				{
					if (tr == null)
						return null;
					var text = tr.ReadToEnd();
					// I've seen people trying to put a data link escape character in their feeds. Bozhe moi!
					if (text.Any(c => !IsXmlChar(c)))
					{
						text = new string(text.Where(IsXmlChar).ToArray());
					}
					return XDocument.Parse(text);
				});
		}

		private T Stream<T>(Uri uri, Func<TextReader, T> f)
		{
			try
			{
				var wr = (HttpWebRequest)WebRequest.Create(uri);
				wr.Method = "GET";
				wr.AutomaticDecompression = DecompressionMethods.Deflate | DecompressionMethods.GZip;
				using (var response = (HttpWebResponse)wr.GetResponse())
				{
					_logger.InfoFormat("wget {0}: response {1} ({2})", uri, response.StatusCode, response.StatusDescription);
					return f(new StreamReader(wr.GetResponse().GetResponseStream()));
				}
			}
			catch (Exception ex)
			{
				_logger.InfoFormat(ex, "failed to get response from URL {0}", uri);
				return default(T);
			}
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

