using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

static class VireListen
{
    public delegate object RouteCall(string method, string path, string body, int line, out int maxOutput);

    const int ListenSlotsMax = 64;
    const int MaxHeaderBlock = 16384;
    const int MaxRequestLine = 8192;
    const int MaxRequestBody = 1000000;
    static readonly SemaphoreSlim ListenSlots = new SemaphoreSlim(ListenSlotsMax, ListenSlotsMax);

    public static void WithCancel(int port, int line, string root, RouteCall route, Func<object, string> show, Action<int> setPort)
    {
        using (CancellationTokenSource cts = new CancellationTokenSource())
        {
            ConsoleCancelEventHandler onCancel = delegate (object sender, ConsoleCancelEventArgs e)
            {
                e.Cancel = true;
                cts.Cancel();
            };
            Console.CancelKeyPress += onCancel;
            try { Run(port, line, cts.Token, root, route, show, setPort); }
            finally { Console.CancelKeyPress -= onCancel; }
        }
    }

    public static void Run(int port, int line, CancellationToken stop, string root, RouteCall route, Func<object, string> show, Action<int> setPort)
    {
        string envPort = Environment.GetEnvironmentVariable("PORT");
        if (!string.IsNullOrWhiteSpace(envPort)) port = Machine.RequirePort(envPort.Trim(), line);
        bool publish = string.Equals(Environment.GetEnvironmentVariable("VIRE_BIND"), "public", StringComparison.Ordinal);
        string token = Environment.GetEnvironmentVariable("FCG_API_TOKEN");
        if (publish && (string.IsNullOrEmpty(token) || token.Length < 16))
            throw new VireError("a public listener needs FCG_API_TOKEN of at least 16 characters", line);
        IPAddress bind = publish ? IPAddress.Any : IPAddress.Loopback;
        TcpListener listener = BindListen(bind, port);
        int actual = ((IPEndPoint)listener.LocalEndpoint).Port;
        if (Machine.IsReservedListenPort(actual))
        {
            listener.Stop();
            throw new VireError("that port is reserved", line);
        }
        setPort(actual);
        Console.WriteLine("listening on " + (publish ? "0.0.0.0:" : "127.0.0.1:") + actual);
        try
        {
            while (!stop.IsCancellationRequested)
            {
                IAsyncResult pending = listener.BeginAcceptTcpClient(null, null);
                WaitHandle[] wait = new WaitHandle[] { pending.AsyncWaitHandle, stop.WaitHandle };
                int which = WaitHandle.WaitAny(wait);
                if (which != 0)
                {
                    try { listener.EndAcceptTcpClient(pending).Close(); } catch (Exception) { }
                    break;
                }
                TcpClient client;
                try { client = listener.EndAcceptTcpClient(pending); }
                catch (ObjectDisposedException) { break; }
                catch (SocketException) { continue; }
                if (!ListenSlots.Wait(0))
                {
                    try { SendApi(client.GetStream(), 503, "{\"error\":\"busy\"}", "Retry-After: 1\r\n"); }
                    catch (Exception) { }
                    try { client.Close(); } catch (Exception) { }
                    continue;
                }
                ThreadPool.QueueUserWorkItem(delegate (object state)
                {
                    TcpClient held = (TcpClient)state;
                    try { AnswerApi(held, line, token, publish, stop, root, route, show); }
                    catch (IOException)
                    {
                        Console.Error.WriteLine("vire: internal error (IOException)");
                    }
                    catch (Exception ex)
                    {
                        Console.Error.WriteLine("vire: internal error (" + ex.GetType().Name + ")");
                    }
                    finally
                    {
                        try { held.Close(); } catch (Exception) { }
                        ListenSlots.Release();
                    }
                }, client);
            }
            DateTime drain = DateTime.UtcNow.AddSeconds(5);
            while (ListenSlots.CurrentCount < ListenSlotsMax && DateTime.UtcNow < drain)
                Thread.Sleep(50);
        }
        finally
        {
            try { listener.Stop(); } catch (Exception) { }
        }
    }

    static TcpListener BindListen(IPAddress bind, int port)
    {
        if (port != 0)
        {
            TcpListener once = new TcpListener(bind, port);
            once.Start();
            return once;
        }
        for (int attempt = 0; attempt < 8; attempt++)
        {
            TcpListener listener = new TcpListener(bind, 0);
            listener.Start();
            int actual = ((IPEndPoint)listener.LocalEndpoint).Port;
            if (!Machine.IsReservedListenPort(actual)) return listener;
            listener.Stop();
        }
        throw new VireError("that port is reserved", 1);
    }

    static int HeaderEnd(byte[] buffer, int got)
    {
        for (int i = 0; i + 3 < got; i++)
            if (buffer[i] == 13 && buffer[i + 1] == 10 && buffer[i + 2] == 13 && buffer[i + 3] == 10) return i;
        return -1;
    }

    static int ContentLengthOf(string head)
    {
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        for (int i = 1; i < lines.Length; i++)
        {
            if (lines[i].StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
            {
                int value;
                if (!int.TryParse(lines[i].Substring(15).Trim(), out value) || value < 0) return -2;
                return value;
            }
        }
        return -1;
    }

    static bool HasChunked(string head)
    {
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        for (int i = 1; i < lines.Length; i++)
        {
            if (lines[i].StartsWith("Transfer-Encoding:", StringComparison.OrdinalIgnoreCase) &&
                lines[i].IndexOf("chunked", StringComparison.OrdinalIgnoreCase) >= 0)
                return true;
        }
        return false;
    }

    static bool ReadTimed(NetworkStream stream, byte[] buffer, ref int got, int want, DateTime deadline)
    {
        while (got < want)
        {
            int remain = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
            if (remain <= 0) return false;
            stream.ReadTimeout = Math.Max(1, remain);
            int n;
            try { n = stream.Read(buffer, got, want - got); }
            catch (IOException) { return false; }
            if (n <= 0) return false;
            got += n;
        }
        return true;
    }

    static bool ReadOnce(NetworkStream stream, byte[] buffer, ref int got, int maxGot, DateTime deadline)
    {
        if (got >= maxGot) return false;
        int remain = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
        if (remain <= 0) return false;
        stream.ReadTimeout = Math.Max(1, remain);
        int n;
        try { n = stream.Read(buffer, got, maxGot - got); }
        catch (IOException) { return false; }
        if (n <= 0) return false;
        got += n;
        return true;
    }

    static void AnswerApi(TcpClient client, int line, string token, bool publish, CancellationToken stop, string root, RouteCall route, Func<object, string> show)
    {
        NetworkStream stream = client.GetStream();
        DateTime headerDead = DateTime.UtcNow.AddSeconds(5);
        byte[] buffer = new byte[MaxHeaderBlock + MaxRequestBody + 16];
        int got = 0;
        int headerEnd = -1;
        while (headerEnd < 0)
        {
            if (stop.IsCancellationRequested) return;
            if (got >= MaxHeaderBlock)
            {
                SendApi(stream, 431, "{\"error\":\"headers too large\"}", null);
                return;
            }
            int before = got;
            if (!ReadOnce(stream, buffer, ref got, MaxHeaderBlock, headerDead))
            {
                if (HeaderEnd(buffer, got) >= 0) break;
                SendApi(stream, 408, "{\"error\":\"timeout\"}", null);
                return;
            }
            if (got == before) { SendApi(stream, 408, "{\"error\":\"timeout\"}", null); return; }
            headerEnd = HeaderEnd(buffer, got);
        }
        if (headerEnd < 0)
        {
            SendApi(stream, 408, "{\"error\":\"timeout\"}", null);
            return;
        }
        int lineEnd = -1;
        for (int i = 0; i + 1 < headerEnd; i++)
        {
            if (buffer[i] == 13 && buffer[i + 1] == 10) { lineEnd = i; break; }
        }
        if (lineEnd < 0 || lineEnd > MaxRequestLine)
        {
            SendApi(stream, 431, "{\"error\":\"request line too large\"}", null);
            return;
        }
        string head = Encoding.ASCII.GetString(buffer, 0, headerEnd);
        string requestLine = Encoding.ASCII.GetString(buffer, 0, lineEnd);
        string[] bits = requestLine.Split(' ');
        if (bits.Length < 2)
        {
            SendApi(stream, 400, "{\"error\":\"bad request\"}", null);
            return;
        }
        if (bits[1].IndexOf("..") >= 0)
        {
            if (bits[0] == "GET" || bits[0] == "HEAD")
                SendSiteEmpty(stream, 404, "text/plain; charset=utf-8", "not found");
            else
                SendApi(stream, 400, "{\"error\":\"bad request\"}", null);
            return;
        }
        if (HasChunked(head))
        {
            SendApi(stream, 501, "{\"error\":\"chunked encoding is not supported\"}", null);
            return;
        }
        int bodyAt = headerEnd + 4;
        int contentLength = ContentLengthOf(head);
        if (contentLength == -2)
        {
            SendApi(stream, 400, "{\"error\":\"bad request\"}", null);
            return;
        }
        string method = bits[0];
        bool expectsBody = method == "POST" || method == "PUT" || method == "PATCH";
        if (expectsBody && contentLength < 0)
        {
            SendApi(stream, 411, "{\"error\":\"content length required\"}", null);
            return;
        }
        if (contentLength > MaxRequestBody)
        {
            SendApi(stream, 413, "{\"error\":\"body too large\"}", null);
            return;
        }
        if (contentLength < 0) contentLength = 0;
        int need = bodyAt + contentLength;
        DateTime bodyDead = DateTime.UtcNow.AddSeconds(10);
        if (got < need)
        {
            if (!ReadTimed(stream, buffer, ref got, need, bodyDead))
            {
                SendApi(stream, got < need ? 408 : 400, "{\"error\":\"timeout\"}", null);
                return;
            }
        }
        string path = bits[1];
        int queryAt = path.IndexOf('?');
        if (queryAt >= 0) path = path.Substring(0, queryAt);
        string body = Encoding.UTF8.GetString(buffer, bodyAt, contentLength);
        if ((method == "GET" || method == "HEAD") && TrySite(stream, method, path, head, line, root))
            return;
        bool health = path == "/health" && (method == "GET" || method == "HEAD");
        bool tokenOn = !string.IsNullOrEmpty(token) && token.Length >= 16;
        if (!health && tokenOn && !Program.HeaderTokenMatches(head, token))
        {
            SendApi(stream, 401, "{\"error\":\"unauthorized\"}", null);
            return;
        }
        if (!health && publish && !tokenOn)
        {
            SendApi(stream, 401, "{\"error\":\"unauthorized\"}", null);
            return;
        }
        object result;
        int maxOutput;
        bool chain = path == "/block" || path == "/chain";
        if (chain) Monitor.Enter(ListenHooks.ChainRouteLock);
        try
        {
            if (ListenHooks.RouteException != null && path == "/boom")
                throw ListenHooks.RouteException;
            result = route(method, path, body, line, out maxOutput);
        }
        catch (VireError err)
        {
            if (IsRequestBudget(err))
                SendApi(stream, 503, "{\"error\":\"busy\"}", "Retry-After: 1\r\n");
            else
                SendApi(stream, 500, "{\"error\":\"route failed\"}", null);
            return;
        }
        catch (HaltSignal)
        {
            SendApi(stream, 500, "{\"error\":\"route failed\"}", null);
            return;
        }
        catch (Exception ex)
        {
            if (Environment.GetEnvironmentVariable("VIRE_DEBUG") == "1")
                Console.Error.WriteLine(ex.ToString());
            else
                Console.Error.WriteLine("vire: internal error (" + ex.GetType().Name + ")");
            try { SendApi(stream, 500, "{\"error\":\"route failed\"}", null); }
            catch (Exception sendError)
            {
                Console.Error.WriteLine("vire: internal error (" + sendError.GetType().Name + ")");
            }
            return;
        }
        finally
        {
            if (chain) Monitor.Exit(ListenHooks.ChainRouteLock);
        }
        string text = result as string;
        if (text == null) text = show(result);
        if (text == null) text = "null";
        if (text.Length > maxOutput) text = "{\"error\":\"response too large\"}";
        int code = StatusOf(text, 200);
        SendApi(stream, code, text, null);
    }

    static bool IsRequestBudget(VireError err)
    {
        string msg = err.Message;
        return msg.IndexOf("request ran too long", StringComparison.Ordinal) >= 0
            || msg.IndexOf("program ran too long", StringComparison.Ordinal) >= 0
            || msg.IndexOf("while ran too long", StringComparison.Ordinal) >= 0;
    }

    static int StatusOf(string text, int fallback)
    {
        if (text == null) return fallback;
        int[] codes = { 507, 503, 500, 431, 413, 411, 408, 404, 403, 401, 400 };
        for (int i = 0; i < codes.Length; i++)
        {
            string needle = "\"status\":" + codes[i];
            if (text.IndexOf(needle, StringComparison.Ordinal) >= 0) return codes[i];
        }
        return fallback;
    }

    static string ReasonOf(int code)
    {
        if (code == 200) return "OK";
        if (code == 206) return "Partial Content";
        if (code == 400) return "Bad Request";
        if (code == 401) return "Unauthorized";
        if (code == 403) return "Forbidden";
        if (code == 404) return "Not Found";
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

    static void SendApi(NetworkStream stream, int code, string body, string extra)
    {
        byte[] data = Encoding.UTF8.GetBytes(body ?? "");
        string head = "HTTP/1.1 " + code + " " + ReasonOf(code) + "\r\n"
            + "Content-Type: application/json; charset=utf-8\r\n"
            + "Content-Length: " + data.Length + "\r\n"
            + "Connection: close\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Cache-Control: no-store\r\n"
            + (extra ?? "")
            + "\r\n";
        byte[] prefix = Encoding.ASCII.GetBytes(head);
        stream.Write(prefix, 0, prefix.Length);
        if (data.Length > 0) stream.Write(data, 0, data.Length);
    }

    static bool TrySite(NetworkStream stream, string method, string url, string head, int line, string root)
    {
        string site = Path.Combine(root, "site");
        if (!Directory.Exists(site)) return false;
        string rel;
        if (!SiteRelative(url, out rel))
        {
            SendSiteEmpty(stream, 404, "text/plain", "not found");
            return true;
        }
        string type;
        long limit;
        if (!SiteType(rel, out type, out limit))
        {
            SendSiteEmpty(stream, 404, "text/plain", "not found");
            return true;
        }
        string full;
        try { full = VirePaths.DataOrSite(root, "site/" + rel, line); }
        catch (VireError)
        {
            SendSiteEmpty(stream, 404, "text/plain", "not found");
            return true;
        }
        if (!File.Exists(full) || Directory.Exists(full)) return false;
        try
        {
            if ((File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0)
            {
                SendSiteEmpty(stream, 404, "text/plain", "not found");
                return true;
            }
        }
        catch (IOException)
        {
            SendSiteEmpty(stream, 404, "text/plain", "not found");
            return true;
        }
        long length = new FileInfo(full).Length;
        if (length > limit)
        {
            SendSiteEmpty(stream, 413, "text/plain", "too large");
            return true;
        }
        long start = 0;
        long count = length;
        bool partial = false;
        bool video = type.StartsWith("video/", StringComparison.Ordinal);
        if (video)
        {
            int rangeStatus = SiteRange(head, length, out start, out count, out partial);
            if (rangeStatus == 416)
            {
                SendSiteRangeFail(stream, type, length);
                return true;
            }
        }
        if (method == "HEAD") count = 0;
        using (FileStream file = File.OpenRead(full))
            SendSiteFile(stream, partial ? 206 : 200, type, file, start, count, partial, length, video);
        return true;
    }

    static bool SiteRelative(string url, out string rel)
    {
        rel = null;
        if (url == null) return false;
        string decoded;
        try { decoded = Uri.UnescapeDataString(url); }
        catch (UriFormatException) { return false; }
        if (decoded.IndexOf('\0') >= 0) return false;
        if (decoded.IndexOf("://", StringComparison.Ordinal) >= 0) return false;
        while (decoded.StartsWith("/", StringComparison.Ordinal)) decoded = decoded.Substring(1);
        if (decoded.Length == 0) decoded = "index.html";
        if (decoded.IndexOf(':') >= 0) return false;
        try { VirePaths.CheckName(decoded, 1); }
        catch (VireError) { return false; }
        rel = decoded;
        return true;
    }

    static bool SiteType(string rel, out string type, out long limit)
    {
        type = null;
        limit = 1000000;
        string ext = VirePaths.NormalizedExtension(rel);
        if (ext == ".html") type = "text/html; charset=utf-8";
        else if (ext == ".css") type = "text/css; charset=utf-8";
        else if (ext == ".js") type = "text/javascript; charset=utf-8";
        else if (ext == ".svg") type = "image/svg+xml";
        else if (ext == ".json") type = "application/json; charset=utf-8";
        else if (ext == ".txt") type = "text/plain; charset=utf-8";
        else if (ext == ".mp4") { type = "video/mp4"; limit = 512000000; }
        else if (ext == ".webm") { type = "video/webm"; limit = 512000000; }
        else if (ext == ".ogv") { type = "video/ogg"; limit = 512000000; }
        return type != null;
    }

    static int SiteRange(string head, long length, out long start, out long count, out bool partial)
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

    static void SendSiteEmpty(NetworkStream stream, int code, string type, string body)
    {
        byte[] data = Encoding.UTF8.GetBytes(body ?? "");
        string head = SiteHead(code, type, data.Length, "", false);
        byte[] prefix = Encoding.ASCII.GetBytes(head);
        stream.Write(prefix, 0, prefix.Length);
        if (data.Length > 0) stream.Write(data, 0, data.Length);
    }

    static void SendSiteRangeFail(NetworkStream stream, string type, long total)
    {
        string extra = "Content-Range: bytes */" + total + "\r\n";
        string head = SiteHead(416, type, 0, extra, true);
        byte[] prefix = Encoding.ASCII.GetBytes(head);
        stream.Write(prefix, 0, prefix.Length);
    }

    static void SendSiteFile(NetworkStream stream, int code, string type, Stream file, long start, long count, bool partial, long total, bool video)
    {
        string extra = "";
        if (partial) extra += "Content-Range: bytes " + start + "-" + (start + count - 1) + "/" + total + "\r\n";
        string head = SiteHead(code, type, count, extra, video);
        byte[] prefix = Encoding.ASCII.GetBytes(head);
        stream.Write(prefix, 0, prefix.Length);
        if (count <= 0) return;
        file.Seek(start, SeekOrigin.Begin);
        byte[] buf = new byte[65536];
        long left = count;
        while (left > 0)
        {
            int n = file.Read(buf, 0, (int)Math.Min(buf.Length, left));
            if (n <= 0) break;
            stream.Write(buf, 0, n);
            left -= n;
        }
    }

    static string SiteHead(int code, string type, long length, string extra, bool acceptRanges)
    {
        return "HTTP/1.1 " + code + " " + ReasonOf(code) + "\r\n"
            + "Content-Type: " + type + "\r\n"
            + "Content-Length: " + length + "\r\n"
            + "Connection: close\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Content-Security-Policy: default-src 'self'\r\n"
            + (acceptRanges ? "Accept-Ranges: bytes\r\n" : "")
            + (extra ?? "")
            + "\r\n";
    }
}
