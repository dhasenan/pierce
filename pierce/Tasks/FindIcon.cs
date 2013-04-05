using System;
using System.Net;
using System.IO;
using System.Linq;

namespace pierce
{
    public class FindIcon
    {
        public Uri Find(Uri feedUrl)
        {
            try
            {
                var baseUrl = new Uri(feedUrl, "/");
                WebRequest wr = WebRequest.Create(baseUrl);
                wr.Method = "GET";
                TextReader tr = new StreamReader(wr.GetResponse().GetResponseStream());
                var text = tr.ReadToEnd();
                var doc = new HtmlAgilityPack.HtmlDocument();
                doc.LoadHtml(text);
                var iconLink = doc.DocumentNode.SelectNodes("//link[@rel='shortcut icon'").FirstOrDefault();
                if (iconLink == null)
                    return null;
                Uri uri;
                if (Uri.TryCreate(baseUrl, iconLink.GetAttributeValue("href", "favicon.ico"), out uri))
                {
                    return uri;
                }
            }
            catch
            {
            }
            return null;
        }
    }
}

