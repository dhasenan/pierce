using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Xml.Linq;
using HtmlAgilityPack;
using System.Net.Cache;
using System.Net.Http;
using System.Xml;
using Microsoft.Extensions.Logging;

namespace Pierce;

public class Wget
{
	private readonly ILogger<Wget> _logger;
	private readonly HttpRequestCachePolicy _policy;
	private HttpClient _http;
	private DateTime _lastRefreshed;

	public Wget(ILogger<Wget> logger)
	{
		this._logger = logger;
		// We shouldn't normally contact the same feed twice within 15 minutes.
		// In case we do, use cached values.
		this._policy = new HttpRequestCachePolicy(HttpCacheAgeControl.MaxAge, TimeSpan.FromMinutes(10));
		_http = new HttpClient();
		_lastRefreshed = DateTime.UtcNow;
	}

	/*
	public async Task<object> Fetch(Uri uri)
	{
		var response = _http.GetAsync(uri);
		if (!response.IsSuccessStatusCode)
		{
			return null;
		}
		var body = await response.Content.ReadAsStringAsync();
	}
	*/

	public Task<string> Text(Uri uri)
	{
		return Stream(uri, (str) => str);
	}

	public Task<HtmlDocument> Html(Uri uri)
	{
		return Stream(uri, (tr) =>
			{
				var doc = new HtmlDocument();
				doc.LoadHtml(tr);
				return doc;
			});
	}

	public Task<XDocument> Xml(Uri uri)
	{
		return Stream(uri, (text) =>
			{
				// I've seen people trying to put a data link escape character in their feeds. Bozhe moi!
				if (text.Any(c => !XmlConvert.IsXmlChar(c)))
				{
					text = new string(text.Where(XmlConvert.IsXmlChar).ToArray());
				}
				return XDocument.Parse(text);
			});
	}

	private async Task<T> Stream<T>(Uri uri, Func<string, T> f)
	{
		if (_lastRefreshed < DateTime.UtcNow - TimeSpan.FromMinutes(10))
		{
			_http = new HttpClient();
			_lastRefreshed = DateTime.UtcNow;
		}
		string s;
		try
		{
			s = await _http.GetStringAsync(uri);
		}
		catch (Exception e)
		{
			_logger.LogInformation($"failed to get response from URL {uri}: {e}");
			throw new Exception($"failed to get response from URL {uri}", e);
		}
		return f(s);
	}
}
