using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

static class VireNet
{
    const int MaxResponse = 1000000;
    const int MaxRedirects = 3;
    const int ConnectTimeoutMs = 5000;
    const int MaxRecv = 1000000;

    internal static Func<string, IPAddress[]> ResolveHost = DefaultResolve;
    internal static Func<string, bool> IsTestOrigin = DefaultTestOrigin;

    static IPAddress[] DefaultResolve(string host)
    {
        return Dns.GetHostAddresses(host);
    }

    static bool DefaultTestOrigin(string host)
    {
        return false;
    }

    internal static void ResetHooks()
    {
        ResolveHost = DefaultResolve;
        IsTestOrigin = DefaultTestOrigin;
    }

    internal static bool IsPublicAddress(IPAddress address)
    {
        if (address == null) return false;
        if (IPAddress.IsLoopback(address)) return false;
        if (address.IsIPv4MappedToIPv6) return IsPublicAddress(address.MapToIPv4());
        if (address.AddressFamily == AddressFamily.InterNetwork)
            return IsPublicV4(address.GetAddressBytes());
        if (address.AddressFamily != AddressFamily.InterNetworkV6) return false;
        byte[] bits = address.GetAddressBytes();
        if (bits.Length != 16) return false;
        if (Zeros(bits, 0, 16)) return false;
        if (Zeros(bits, 0, 15) && bits[15] == 1) return false;
        if (Zeros(bits, 0, 12))
            return IsPublicAddress(new IPAddress(new byte[] { bits[12], bits[13], bits[14], bits[15] }));
        if (Zeros(bits, 0, 10) && bits[10] == 0xff && bits[11] == 0xff)
            return IsPublicAddress(new IPAddress(new byte[] { bits[12], bits[13], bits[14], bits[15] }));
        if (Zeros(bits, 0, 8) && bits[8] == 0xff && bits[9] == 0xff && bits[10] == 0 && bits[11] == 0)
            return IsPublicAddress(new IPAddress(new byte[] { bits[12], bits[13], bits[14], bits[15] }));
        if (bits[0] == 0x20 && bits[1] == 0x02)
            return IsPublicAddress(new IPAddress(new byte[] { bits[2], bits[3], bits[4], bits[5] }));
        if (bits[0] == 0x00 && bits[1] == 0x64 && bits[2] == 0xff && bits[3] == 0x9b && Zeros(bits, 4, 8))
            return IsPublicAddress(new IPAddress(new byte[] { bits[12], bits[13], bits[14], bits[15] }));
        // RFC 8215 local-use NAT64. The embedded IPv4 is not a global destination.
        if (bits[0] == 0x00 && bits[1] == 0x64 && bits[2] == 0xff && bits[3] == 0x9b && bits[4] == 0x00 && bits[5] == 0x01)
            return false;
        if (bits[0] == 0x20 && bits[1] == 0x01 && bits[2] == 0x00 && bits[3] == 0x00) return false;
        if (bits[0] == 0x20 && bits[1] == 0x01 && bits[2] == 0x0d && bits[3] == 0xb8) return false;
        if (bits[0] == 0xff) return false;
        if (bits[0] == 0xfe && (bits[1] & 0xc0) == 0x80) return false;
        if (bits[0] == 0xfe && (bits[1] & 0xc0) == 0xc0) return false;
        if ((bits[0] & 0xfe) == 0xfc) return false;
        return true;
    }

    static bool IsPublicV4(byte[] part)
    {
        if (part == null || part.Length != 4) return false;
        if (part[0] == 0 || part[0] == 10 || part[0] == 127) return false;
        if (part[0] == 169 && part[1] == 254) return false;
        if (part[0] == 172 && part[1] >= 16 && part[1] <= 31) return false;
        if (part[0] == 192 && part[1] == 168) return false;
        if (part[0] == 100 && part[1] >= 64 && part[1] <= 127) return false;
        if (part[0] == 198 && (part[1] == 18 || part[1] == 19)) return false;
        if (part[0] == 192 && part[1] == 88 && part[2] == 99) return false;
        if (part[0] == 192 && part[1] == 0 && part[2] == 0) return false;
        if (part[0] == 192 && part[1] == 0 && part[2] == 2) return false;
        if (part[0] == 198 && part[1] == 51 && part[2] == 100) return false;
        if (part[0] == 203 && part[1] == 0 && part[2] == 113) return false;
        if (part[0] >= 224) return false;
        return true;
    }

    static bool Zeros(byte[] bits, int at, int count)
    {
        for (int n = 0; n < count; n++) if (bits[at + n] != 0) return false;
        return true;
    }

    internal static IPAddress DemandFetchPin(string url, int line, int column)
    {
        Uri parsed;
        if (!Uri.TryCreate(url, UriKind.Absolute, out parsed) || parsed.Host.Length == 0)
            throw new VireError("that address is not allowed", line, column);
        if (!string.IsNullOrEmpty(parsed.UserInfo))
            throw new VireError("that address is not allowed", line, column);
        IPAddress literal;
        if (IPAddress.TryParse(parsed.IdnHost, out literal))
        {
            if (literal.IsIPv4MappedToIPv6) literal = literal.MapToIPv4();
            byte[] part = literal.GetAddressBytes();
            if (literal.AddressFamily == AddressFamily.InterNetwork && part.Length == 4
                && part[0] == 127 && part[1] == 0 && part[2] == 0 && part[3] == 1)
            {
                if (parsed.Scheme != "https")
                    throw new VireError("fetch allows https only", line, column);
                return literal;
            }
        }
        return DemandPublic(url, line, column);
    }

    internal static IPAddress DemandPublic(string url, int line)
    {
        return DemandPublic(url, line, 1);
    }

    internal static IPAddress DemandPublic(string url, int line, int column)
    {
        Uri parsed;
        if (!Uri.TryCreate(url, UriKind.Absolute, out parsed) || parsed.Host.Length == 0)
            throw new VireError("that address is not allowed", line, column);
        if (parsed.Scheme != "http" && parsed.Scheme != "https")
            throw new VireError("that address is not allowed", line, column);
        if (!string.IsNullOrEmpty(parsed.UserInfo))
            throw new VireError("that address is not allowed", line, column);
        string host = parsed.IdnHost;
        if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
            throw new VireError("fetch stays off this machine and private networks", line, column);
        bool testOrigin = IsTestOrigin(host);
        IPAddress literal;
        if (IPAddress.TryParse(host, out literal))
        {
            if (testOrigin) return literal;
            if (!IsPublicAddress(literal))
                throw new VireError("fetch stays off this machine and private networks", line, column);
            if (parsed.Scheme != "https")
                throw new VireError("fetch allows https only", line, column);
            return literal;
        }
        if (!testOrigin && parsed.Scheme != "https")
            throw new VireError("fetch allows https only", line, column);
        IPAddress[] addresses;
        try { addresses = ResolveHost(host); }
        catch (Exception) { throw new VireError("could not check that address", line, column); }
        if (addresses == null || addresses.Length == 0)
            throw new VireError("could not check that address", line, column);
        IPAddress chosen = null;
        for (int i = 0; i < addresses.Length; i++)
        {
            IPAddress address = addresses[i];
            if (!testOrigin && !IsPublicAddress(address))
                throw new VireError("fetch stays off this machine and private networks", line, column);
            if (chosen == null) chosen = address;
        }
        if (chosen == null) throw new VireError("could not check that address", line, column);
        return chosen;
    }

    internal static string SendWeb(HttpMethod method, string url, string body, int line)
    {
        return SendWeb(method, url, body, line, 1);
    }

    internal static string SendWeb(HttpMethod method, string url, string body, int line, int column)
    {
        string current = url;
        HttpMethod verb = method;
        string payload = body;
        for (int hop = 0; hop <= MaxRedirects; hop++)
        {
            IPAddress pinned = DemandFetchPin(current, line, column);
            int code;
            string location;
            string text = SendPinned(verb, current, payload, pinned, line, column, out code, out location);
            if (code >= 300 && code <= 399)
            {
                if (hop == MaxRedirects)
                    throw new VireError("too many redirects", line, column);
                if (string.IsNullOrEmpty(location))
                    throw new VireError("that address is not allowed", line, column);
                Uri nextAbs;
                if (!Uri.TryCreate(location, UriKind.Absolute, out nextAbs))
                    nextAbs = new Uri(new Uri(current), location);
                current = nextAbs.AbsoluteUri;
                payload = null;
                verb = HttpMethod.Get;
                continue;
            }
            if (code < 200 || code >= 300) throw new VireError("the address returned " + code, line, column);
            return text;
        }
        throw new VireError("too many redirects", line, column);
    }

    static string SendPinned(HttpMethod method, string url, string body, IPAddress pinned, int line, int column, out int code, out string location)
    {
        SocketsHttpHandler handler = new SocketsHttpHandler();
        handler.AllowAutoRedirect = false;
        handler.UseProxy = false;
        IPAddress pin = pinned;
        handler.ConnectCallback = (context, token) => ConnectPinned(pin, context.DnsEndPoint.Port, token);
        using (HttpClient client = new HttpClient(handler))
        using (CancellationTokenSource cancel = new CancellationTokenSource(TimeSpan.FromSeconds(8)))
        {
            client.Timeout = Timeout.InfiniteTimeSpan;
            using (HttpRequestMessage message = new HttpRequestMessage(method, url))
            {
                if (body != null) message.Content = new StringContent(body, Encoding.UTF8, "text/plain");
                HttpResponseMessage response;
                try { response = client.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancel.Token).GetAwaiter().GetResult(); }
                catch (VireError) { throw; }
                catch (Exception) { throw new VireError("could not reach that address", line, column); }
                using (response)
                {
                    code = (int)response.StatusCode;
                    location = response.Headers.Location == null ? null : response.Headers.Location.ToString();
                    return ReadLimited(response, line, column, cancel.Token);
                }
            }
        }
    }

    static string ReadLimited(HttpResponseMessage response, int line, int column, CancellationToken cancel)
    {
        using (Stream stream = response.Content.ReadAsStream())
        {
            MemoryStream buffer = new MemoryStream();
            byte[] chunk = new byte[8192];
            int total = 0;
            while (true)
            {
                int n;
                try { n = stream.ReadAsync(chunk, 0, chunk.Length, cancel).GetAwaiter().GetResult(); }
                catch (VireError) { throw; }
                catch (Exception) { throw new VireError("could not reach that address", line, column); }
                if (n <= 0) break;
                total += n;
                if (total > MaxResponse) throw new VireError("the response is too large", line, column);
                buffer.Write(chunk, 0, n);
            }
            return Encoding.UTF8.GetString(buffer.ToArray());
        }
    }

    static async ValueTask<Stream> ConnectPinned(IPAddress pinned, int port, CancellationToken cancel)
    {
        Socket socket = new Socket(pinned.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
        try
        {
            await socket.ConnectAsync(pinned, port, cancel).ConfigureAwait(false);
            return new NetworkStream(socket, true);
        }
        catch (Exception)
        {
            socket.Dispose();
            throw;
        }
    }

    internal static IPAddress DemandConnectAddress(string host, int line, int column)
    {
        if (string.IsNullOrEmpty(host))
            throw new VireError("that address is not allowed", line, column);
        IPAddress literal;
        if (!IPAddress.TryParse(host, out literal))
            throw new VireError("that address is not allowed", line, column);
        if (literal.IsIPv4MappedToIPv6) literal = literal.MapToIPv4();
        if (literal.AddressFamily != AddressFamily.InterNetwork)
            throw new VireError("that address is not allowed", line, column);
        byte[] part = literal.GetAddressBytes();
        if (part.Length == 4 && part[0] == 127 && part[1] == 0 && part[2] == 0 && part[3] == 1)
            return literal;
        throw new VireError("connect stays off this machine and private networks", line, column);
    }

    internal static int ConnectHost(string host, object portObj, VireTcpTable table, int line, int column)
    {
        if (host == null)
            throw new VireError("connect needs a host and a port", line, column);
        if (!(portObj is int))
            throw new VireError("connect needs a host and a port", line, column);
        int port = (int)portObj;
        if (port < 1 || port > 65535)
            throw new VireError("connect needs a port from 1 to 65535", line, column);
        IPAddress pinned = DemandConnectAddress(host, line, column);
        Socket socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        try
        {
            socket.NoDelay = true;
            socket.ReceiveTimeout = ConnectTimeoutMs;
            socket.SendTimeout = ConnectTimeoutMs;
            IAsyncResult wait = socket.BeginConnect(pinned, port, null, null);
            if (!wait.AsyncWaitHandle.WaitOne(ConnectTimeoutMs))
            {
                try { socket.Close(); } catch (Exception) { }
                throw new VireError("could not connect", line, column);
            }
            socket.EndConnect(wait);
            return table.Put(socket);
        }
        catch (VireError)
        {
            socket.Dispose();
            throw;
        }
        catch (Exception)
        {
            socket.Dispose();
            throw new VireError("could not connect", line, column);
        }
    }

    internal static int SendAll(object handle, object payload, VireTcpTable table, int line, int column)
    {
        Socket socket = table.Need(handle, line, column);
        string text = payload as string;
        if (text == null) throw new VireError("send needs a connection and text", line, column);
        // Latin-1 / raw bytes 0-255 so Postgres frontend v3 (and native PE) stay 1:1.
        byte[] raw = new byte[text.Length];
        for (int i = 0; i < text.Length; i++)
        {
            int c = text[i];
            if (c > 255) throw new VireError("send needs a connection and text", line, column);
            raw[i] = (byte)c;
        }
        int off = 0;
        try
        {
            while (off < raw.Length)
            {
                int n = socket.Send(raw, off, raw.Length - off, SocketFlags.None);
                if (n <= 0) throw new VireError("could not connect", line, column);
                off += n;
            }
        }
        catch (VireError) { throw; }
        catch (Exception) { throw new VireError("could not connect", line, column); }
        return raw.Length;
    }

    internal static string RecvBound(object handle, object maxObj, VireTcpTable table, int line, int column)
    {
        Socket socket = table.Need(handle, line, column);
        if (!(maxObj is int)) throw new VireError("recv needs a connection and a size", line, column);
        int max = (int)maxObj;
        if (max < 0) throw new VireError("recv needs a connection and a size", line, column);
        if (max > MaxRecv) max = MaxRecv;
        if (max == 0) return "";
        byte[] buf = new byte[max];
        try
        {
            int n = socket.Receive(buf, 0, max, SocketFlags.None);
            if (n <= 0) return "";
            char[] chars = new char[n];
            for (int i = 0; i < n; i++) chars[i] = (char)buf[i];
            return new string(chars);
        }
        catch (VireError) { throw; }
        catch (Exception) { throw new VireError("could not connect", line, column); }
    }

    internal static object CloseHandle(object handle, VireTcpTable table, int line, int column)
    {
        table.Close(handle, line, column);
        return null;
    }
}

sealed class VireTcpTable
{
    int next = 1;
    readonly Dictionary<int, Socket> live = new Dictionary<int, Socket>();

    internal int Put(Socket socket)
    {
        int id = next++;
        live[id] = socket;
        return id;
    }

    internal Socket Need(object handle, int line, int column)
    {
        if (!(handle is int)) throw new VireError("that connection is closed", line, column);
        Socket socket;
        if (!live.TryGetValue((int)handle, out socket) || socket == null)
            throw new VireError("that connection is closed", line, column);
        return socket;
    }

    internal void Close(object handle, int line, int column)
    {
        Socket socket = Need(handle, line, column);
        live.Remove((int)handle);
        try { socket.Close(); }
        catch (Exception) { throw new VireError("that connection is closed", line, column); }
    }
}
