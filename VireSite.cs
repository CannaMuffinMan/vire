using System;
using System.Globalization;
using System.IO;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

static class VireSite
{
    const long DefaultLimit = 1000000;
    const long VideoLimit = 512000000;

    public static bool Try(NetworkStream stream, string method, string url, string head, int line, string root)
    {
        string siteRel;
        if (!DeclaredRoot(root, out siteRel)) return false;
        string site = Path.Combine(root, siteRel.Replace('/', Path.DirectorySeparatorChar));
        if (!Directory.Exists(site)) return false;
        bool writeBody = method == "GET";
        bool headOnly = method == "HEAD";
        if (!writeBody && !headOnly)
        {
            string probeRel;
            if (SiteRelative(url, out probeRel) && File.Exists(Path.Combine(site, probeRel.Replace('/', Path.DirectorySeparatorChar))))
            {
                SendEmpty(stream, 405, "text/html; charset=utf-8", "<html>method not allowed</html>");
                return true;
            }
            return false;
        }
        string rel;
        if (!SiteRelative(url, out rel))
        {
            SendEmpty(stream, 404, "text/html; charset=utf-8", "<html>not found</html>");
            return true;
        }
        string type;
        long limit;
        if (!SiteType(rel, out type, out limit)) return false;
        string full;
        try { full = VirePaths.DataOrSite(root, siteRel + "/" + rel, line); }
        catch (VireError)
        {
            SendEmpty(stream, 404, "text/html; charset=utf-8", "<html>not found</html>");
            return true;
        }
        string siteRoot = Path.GetFullPath(site);
        if (!VirePaths.InFolder(siteRoot, full))
        {
            SendEmpty(stream, 404, "text/html; charset=utf-8", "<html>not found</html>");
            return true;
        }
        if (!File.Exists(full) || Directory.Exists(full)) return false;
        try
        {
            if ((File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0)
            {
                SendEmpty(stream, 404, "text/html; charset=utf-8", "<html>not found</html>");
                return true;
            }
        }
        catch (IOException)
        {
            SendEmpty(stream, 404, "text/html; charset=utf-8", "<html>not found</html>");
            return true;
        }
        byte[] data = File.ReadAllBytes(full);
        if (type.StartsWith("text/html", StringComparison.Ordinal))
            data = Encoding.UTF8.GetBytes(Expand(Encoding.UTF8.GetString(data)));
        if (data.LongLength > limit)
        {
            SendEmpty(stream, 413, "text/plain; charset=utf-8", "too large");
            return true;
        }
        DateTime mtime = File.GetLastWriteTimeUtc(full);
        string etag = ETagOf(data);
        string lastMod = mtime.ToString("r", CultureInfo.InvariantCulture);
        if (NotModified(head, etag, mtime))
        {
            SendMeta(stream, 304, type, 0, etag, lastMod, false);
            return true;
        }
        long start = 0;
        long count = data.LongLength;
        bool partial = false;
        bool video = type.StartsWith("video/", StringComparison.Ordinal);
        if (video)
        {
            int rangeStatus = VireListenRange.Parse(head, data.LongLength, out start, out count, out partial);
            if (rangeStatus == 416)
            {
                SendMeta(stream, 416, type, 0, etag, lastMod, true);
                return true;
            }
        }
        string extra = "ETag: " + etag + "\r\nLast-Modified: " + lastMod + "\r\nCache-Control: public, max-age=60\r\n";
        if (partial) extra += "Content-Range: bytes " + start + "-" + (start + count - 1) + "/" + data.LongLength + "\r\n";
        string headOut = SiteHead(partial ? 206 : 200, type, count, extra, video);
        byte[] prefix = Encoding.ASCII.GetBytes(headOut);
        stream.Write(prefix, 0, prefix.Length);
        if (!writeBody) return true;
        stream.Write(data, (int)start, (int)count);
        return true;
    }

    public static bool DeclaredRoot(string programRoot, out string rel)
    {
        rel = "site";
        string env = Environment.GetEnvironmentVariable("VIRE_SITE_ROOT");
        if (!string.IsNullOrWhiteSpace(env)) rel = env.Trim().Replace('\\', '/');
        if (rel.IndexOf("..", StringComparison.Ordinal) >= 0) return false;
        if (rel.Length == 0) return false;
        if (rel[0] == '/') return false;
        if (!rel.Equals("site", StringComparison.Ordinal) && !rel.EndsWith("/site", StringComparison.Ordinal))
            return false;
        try { VirePaths.CheckName(rel, 1); }
        catch (VireError) { return false; }
        string cap = Environment.GetEnvironmentVariable("VIRE_SITE_CAP");
        if (string.IsNullOrEmpty(cap)) cap = "1";
        if (cap != "1") return false;
        return Directory.Exists(programRoot);
    }

    public static string Expand(string html)
    {
        if (html == null) return "";
        return html.Replace("{{year}}", "2026").Replace("{{payments}}", "off");
    }

    static string ETagOf(byte[] data)
    {
        byte[] hash = SHA256.HashData(data);
        StringBuilder sb = new StringBuilder(68);
        sb.Append("W/\"");
        for (int i = 0; i < hash.Length; i++) sb.Append(hash[i].ToString("x2", CultureInfo.InvariantCulture));
        sb.Append('"');
        return sb.ToString();
    }

    static bool NotModified(string head, string etag, DateTime mtime)
    {
        if (string.IsNullOrEmpty(head)) return false;
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        for (int i = 1; i < lines.Length; i++)
        {
            string line = lines[i];
            if (line.StartsWith("If-None-Match:", StringComparison.OrdinalIgnoreCase))
            {
                string got = line.Substring(14).Trim();
                return string.Equals(got, etag, StringComparison.Ordinal);
            }
            if (line.StartsWith("If-Modified-Since:", StringComparison.OrdinalIgnoreCase))
            {
                string got = line.Substring(18).Trim();
                DateTime parsed;
                if (DateTime.TryParseExact(got, "r", CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out parsed))
                    return parsed.ToUniversalTime() >= mtime.AddTicks(-(mtime.Ticks % TimeSpan.TicksPerSecond));
            }
        }
        return false;
    }

    public static bool SiteRelative(string url, out string rel)
    {
        rel = null;
        if (url == null) return false;
        string decoded;
        try { decoded = Uri.UnescapeDataString(url); }
        catch (UriFormatException) { return false; }
        if (decoded.IndexOf('\0') >= 0) return false;
        if (decoded.IndexOf('\\') >= 0) return false;
        if (decoded.IndexOf("..", StringComparison.Ordinal) >= 0) return false;
        if (decoded.IndexOf("://", StringComparison.Ordinal) >= 0) return false;
        while (decoded.StartsWith("/", StringComparison.Ordinal)) decoded = decoded.Substring(1);
        if (decoded.Length == 0) decoded = "index.html";
        if (decoded.IndexOf(':') >= 0) return false;
        try { VirePaths.CheckName(decoded, 1); }
        catch (VireError) { return false; }
        rel = decoded;
        return true;
    }

    public static bool SiteType(string rel, out string type, out long limit)
    {
        type = null;
        limit = DefaultLimit;
        string ext = VirePaths.NormalizedExtension(rel);
        if (ext == ".html") type = "text/html; charset=utf-8";
        else if (ext == ".css") type = "text/css; charset=utf-8";
        else if (ext == ".js") type = "text/javascript; charset=utf-8";
        else if (ext == ".svg") type = "image/svg+xml";
        else if (ext == ".json") type = "application/json; charset=utf-8";
        else if (ext == ".txt") type = "text/plain; charset=utf-8";
        else if (ext == ".md") type = "text/markdown; charset=utf-8";
        else if (ext == ".xml") type = "application/xml; charset=utf-8";
        else if (ext == ".webmanifest") type = "application/manifest+json";
        else if (ext == ".png") type = "image/png";
        else if (ext == ".jpg" || ext == ".jpeg") type = "image/jpeg";
        else if (ext == ".gif") type = "image/gif";
        else if (ext == ".ico") type = "image/x-icon";
        else if (ext == ".webp") type = "image/webp";
        else if (ext == ".mp4") { type = "video/mp4"; limit = VideoLimit; }
        else if (ext == ".webm") { type = "video/webm"; limit = VideoLimit; }
        else if (ext == ".ogv") { type = "video/ogg"; limit = VideoLimit; }
        return type != null;
    }

    static void SendEmpty(NetworkStream stream, int code, string type, string body)
    {
        byte[] data = Encoding.UTF8.GetBytes(body ?? "");
        string extra = "Cache-Control: no-store\r\n";
        string head = SiteHead(code, type, data.Length, extra, false);
        byte[] prefix = Encoding.ASCII.GetBytes(head);
        stream.Write(prefix, 0, prefix.Length);
        if (data.Length > 0) stream.Write(data, 0, data.Length);
    }

    static void SendMeta(NetworkStream stream, int code, string type, long length, string etag, string lastMod, bool acceptRanges)
    {
        string extra = "ETag: " + etag + "\r\nLast-Modified: " + lastMod + "\r\nCache-Control: public, max-age=60\r\n";
        string head = SiteHead(code, type, length, extra, acceptRanges);
        byte[] prefix = Encoding.ASCII.GetBytes(head);
        stream.Write(prefix, 0, prefix.Length);
    }

    static string HeaderField(string value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        for (int i = 0; i < value.Length; i++)
        {
            char ch = value[i];
            if (ch == '\0') return null;
            if (ch == '\r' || ch == '\n')
            {
                if (ch == '\n') return null;
                if (i + 1 >= value.Length || value[i + 1] != '\n') return null;
                i++;
                if (i + 1 < value.Length && (value[i + 1] == ' ' || value[i + 1] == '\t')) return null;
            }
        }
        if (value.IndexOf("\r\n\r\n", StringComparison.Ordinal) >= 0) return null;
        return value;
    }

    public static string SiteHead(int code, string type, long length, string extra, bool acceptRanges)
    {
        string typeSafe = HeaderField(type);
        string extraSafe = HeaderField(extra);
        if (typeSafe == null || extra != null && extraSafe == null || typeSafe.IndexOf('\r') >= 0 || typeSafe.IndexOf('\n') >= 0)
        {
            typeSafe = "text/plain; charset=utf-8";
            extraSafe = "";
            code = 500;
            length = 0;
        }
        if (extraSafe == null) extraSafe = "";
        return "HTTP/1.1 " + code + " " + ReasonOf(code) + "\r\n"
            + "Content-Type: " + typeSafe + "\r\n"
            + "Content-Length: " + length + "\r\n"
            + "Connection: close\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Content-Security-Policy: default-src 'self'\r\n"
            + (acceptRanges ? "Accept-Ranges: bytes\r\n" : "")
            + extraSafe
            + "\r\n";
    }

    public static string ReasonOf(int code)
    {
        if (code == 200) return "OK";
        if (code == 206) return "Partial Content";
        if (code == 304) return "Not Modified";
        if (code == 400) return "Bad Request";
        if (code == 401) return "Unauthorized";
        if (code == 403) return "Forbidden";
        if (code == 404) return "Not Found";
        if (code == 405) return "Method Not Allowed";
        if (code == 408) return "Request Timeout";
        if (code == 411) return "Length Required";
        if (code == 413) return "Payload Too Large";
        if (code == 416) return "Range Not Satisfiable";
        if (code == 431) return "Request Header Fields Too Large";
        if (code == 500) return "Internal Server Error";
        if (code == 501) return "Not Implemented";
        if (code == 503) return "Service Unavailable";
        if (code == 507) return "Insufficient Storage";
        return "OK";
    }
}

static class VireListenRange
{
    public static int Parse(string head, long length, out long start, out long count, out bool partial)
    {
        start = 0;
        count = length;
        partial = false;
        if (length <= 0) return 200;
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        string spec = null;
        for (int i = 1; i < lines.Length; i++)
        {
            if (lines[i].StartsWith("Range:", StringComparison.OrdinalIgnoreCase))
            {
                spec = lines[i].Substring(6).Trim();
                break;
            }
        }
        if (spec == null) return 200;
        if (!spec.StartsWith("bytes=", StringComparison.OrdinalIgnoreCase)) return 416;
        spec = spec.Substring(6);
        int dash = spec.IndexOf('-');
        if (dash < 0) return 416;
        string left = spec.Substring(0, dash).Trim();
        string right = spec.Substring(dash + 1).Trim();
        long from;
        long to;
        if (left.Length == 0)
        {
            long suffix;
            if (!long.TryParse(right, out suffix) || suffix <= 0) return 416;
            from = Math.Max(0, length - suffix);
            to = length - 1;
        }
        else
        {
            if (!long.TryParse(left, out from)) return 416;
            if (right.Length == 0) to = length - 1;
            else if (!long.TryParse(right, out to)) return 416;
        }
        if (from < 0 || to < from || from >= length) return 416;
        if (to >= length) to = length - 1;
        start = from;
        count = to - from + 1;
        partial = true;
        return 206;
    }
}
