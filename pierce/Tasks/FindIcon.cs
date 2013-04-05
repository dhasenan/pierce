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
                var iconLink = doc.DocumentNode.SelectNodes("//link[@rel='shortcut icon']").FirstOrDefault();
                if (iconLink == null)
                {
                    Console.WriteLine("failed to find icon link");
                    return null;
                }
                Console.WriteLine("found link at base url {0}", baseUrl);
                Uri uri;
                if (Uri.TryCreate(baseUrl, iconLink.GetAttributeValue("href", "favicon.ico"), out uri))
                {
                    Console.WriteLine("found icon at {0}", uri);
                    return uri;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("caught exception {0}", ex);
            }
            return null;
        }
    }
}

