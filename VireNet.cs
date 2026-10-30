using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;

static class VireNet
{
    const int MaxResponse = 1000000;
    const int MaxRedirects = 3;

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

    internal static IPAddress DemandPublic(string url, int line)
    {
        Uri parsed;
        if (!Uri.TryCreate(url, UriKind.Absolute, out parsed) || parsed.Host.Length == 0)
            throw new VireError("that address is not allowed", line);
        if (parsed.Scheme != "http" && parsed.Scheme != "https")
            throw new VireError("that address is not allowed", line);
        if (!string.IsNullOrEmpty(parsed.UserInfo))
            throw new VireError("that address is not allowed", line);
        string host = parsed.IdnHost;
        if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
            throw new VireError("fetch stays off this machine and private networks", line);
        bool testOrigin = IsTestOrigin(host);
        IPAddress literal;
        if (IPAddress.TryParse(host, out literal))
        {
            if (testOrigin) return literal;
            if (!IsPublicAddress(literal))
                throw new VireError("fetch stays off this machine and private networks", line);
            if (parsed.Scheme != "https")
                throw new VireError("fetch allows https only", line);
            return literal;
        }
        if (!testOrigin && parsed.Scheme != "https")
            throw new VireError("fetch allows https only", line);
        IPAddress[] addresses;
        try { addresses = ResolveHost(host); }
        catch (Exception) { throw new VireError("could not check that address", line); }
        if (addresses == null || addresses.Length == 0)
            throw new VireError("could not check that address", line);
        IPAddress chosen = null;
        for (int i = 0; i < addresses.Length; i++)
        {
            IPAddress address = addresses[i];
            if (!testOrigin && !IsPublicAddress(address))
                throw new VireError("fetch stays off this machine and private networks", line);
            if (chosen == null) chosen = address;
        }
        if (chosen == null) throw new VireError("could not check that address", line);
        return chosen;
    }

    internal static string SendWeb(HttpMethod method, string url, string body, int line)
    {
        string current = url;
        HttpMethod verb = method;
        string payload = body;
        for (int hop = 0; hop <= MaxRedirects; hop++)
        {
            IPAddress pinned = DemandPublic(current, line);
            int code;
            string location;
            string text = SendPinned(verb, current, payload, pinned, line, out code, out location);
            if (code >= 300 && code <= 399)
            {
                if (hop == MaxRedirects)
                    throw new VireError("too many redirects", line);
                if (string.IsNullOrEmpty(location))
                    throw new VireError("that address is not allowed", line);
                Uri nextAbs;
                if (!Uri.TryCreate(location, UriKind.Absolute, out nextAbs))
                    nextAbs = new Uri(new Uri(current), location);
                current = nextAbs.AbsoluteUri;
                payload = null;
                verb = HttpMethod.Get;
                continue;
            }
            if (code < 200 || code >= 300) throw new VireError("the address returned " + code, line);
            return text;
        }
        throw new VireError("too many redirects", line);
    }

    static string SendPinned(HttpMethod method, string url, string body, IPAddress pinned, int line, out int code, out string location)
    {
        SocketsHttpHandler handler = new SocketsHttpHandler();
        handler.AllowAutoRedirect = false;
        IPAddress pin = pinned;
        handler.ConnectCallback = (context, token) => ConnectPinned(pin, context.DnsEndPoint.Port);
        using (HttpClient client = new HttpClient(handler))
        {
            client.Timeout = TimeSpan.FromSeconds(8);
            using (HttpRequestMessage message = new HttpRequestMessage(method, url))
            {
                if (body != null) message.Content = new StringContent(body, Encoding.UTF8, "text/plain");
                HttpResponseMessage response;
                try { response = client.SendAsync(message).GetAwaiter().GetResult(); }
                catch (VireError) { throw; }
                catch (Exception) { throw new VireError("could not reach that address", line); }
                using (response)
                {
                    code = (int)response.StatusCode;
                    location = response.Headers.Location == null ? null : response.Headers.Location.ToString();
                    return ReadLimited(response, line);
                }
            }
        }
    }

    static string ReadLimited(HttpResponseMessage response, int line)
    {
        using (Stream stream = response.Content.ReadAsStream())
        {
            MemoryStream buffer = new MemoryStream();
            byte[] chunk = new byte[8192];
            int total = 0;
            while (true)
            {
                int n = stream.Read(chunk, 0, chunk.Length);
                if (n <= 0) break;
                total += n;
                if (total > MaxResponse) throw new VireError("the response is too large", line);
                buffer.Write(chunk, 0, n);
            }
            return Encoding.UTF8.GetString(buffer.ToArray());
        }
    }

    static ValueTask<Stream> ConnectPinned(IPAddress pinned, int port)
    {
        Socket socket = new Socket(pinned.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
        try
        {
            socket.Connect(pinned, port);
            return new ValueTask<Stream>(new NetworkStream(socket, true));
        }
        catch (Exception)
        {
            socket.Dispose();
            throw;
        }
    }
}
