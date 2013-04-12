using System;
using System.Net;
using System.IO;
using System.Linq;
using Castle.Core.Logging;

namespace pierce
{
    public class FindIcon
    {
        ILogger _logger;
        Wget _wget;

        public FindIcon(Wget wget, ILogger logger)
        {
            _wget = wget;
            _logger = logger;
        }

        public Uri Find(Uri feedUrl)
        {
            try
            {
                var baseUrl = new Uri(feedUrl, "/");
                var doc = _wget.Html(baseUrl);
                var iconLinks = doc.DocumentNode.SelectNodes("//link[@rel='shortcut icon']");
                if (iconLinks == null || !iconLinks.Any())
                {
                    _logger.InfoFormat("failed to find icon link");
                    return null;
                }
                var iconLink = iconLinks.FirstOrDefault();
                _logger.InfoFormat("found link at base url {0}", baseUrl);
                Uri uri;
                if (Uri.TryCreate(baseUrl, iconLink.GetAttributeValue("href", "favicon.ico"), out uri))
                {
                    _logger.InfoFormat("found icon at {0}", uri);
                    return uri;
                }
            }
            catch (Exception ex)
            {
                _logger.Error("caught exception", ex);
            }
            return null;
        }
    }
}

