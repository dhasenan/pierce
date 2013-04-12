using System;
using System.IO;
using System.Net;
using System.Xml.Linq;
using HtmlAgilityPack;

namespace pierce
{
    public class Wget
    {
        public HtmlDocument Html(Uri uri)
        {
            var tr = Stream(uri);
            if (tr == null) return null;
            var text = tr.ReadToEnd();
            var doc = new HtmlDocument();
            doc.LoadHtml(text);
            return doc;
        }

        public XDocument Xml(Uri uri)
        {
            var tr = Stream(uri);
            if (tr == null) return null;
            var text = tr.ReadToEnd();
            return XDocument.Parse(text);
        }

        private TextReader Stream(Uri uri)
        {
            try
            {
                WebRequest wr = WebRequest.Create(uri);
                wr.Method = "GET";
                return new StreamReader(wr.GetResponse().GetResponseStream());
            }
            catch
            {
                return null;
            }
        }
    }
}

