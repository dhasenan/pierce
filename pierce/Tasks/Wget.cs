using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Xml.Linq;
using HtmlAgilityPack;

namespace pierce
{
    public class Wget
    {
        public string Text(Uri uri)
        {
            var str = Stream(uri);
            if (str == null)
            {
                return null;
            }
            return str.ReadToEnd();
        }

        public HtmlDocument Html(Uri uri)
        {
            var tr = Stream(uri);
            if (tr == null)
                return null;
            var text = tr.ReadToEnd();
            var doc = new HtmlDocument();
            doc.LoadHtml(text);
            return doc;
        }

        public XDocument Xml(Uri uri)
        {
            var tr = Stream(uri);
            if (tr == null)
                return null;
            var text = tr.ReadToEnd();
            // I've seen people trying to put a data link escape character in their feeds. Bozhe moi!
            if (text.Any(c => !IsXmlChar(c)))
            {
                text = new string(text.Where(IsXmlChar).ToArray());
            }
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

