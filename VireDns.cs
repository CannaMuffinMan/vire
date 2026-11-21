using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

static class VireDns
{
    internal const int MaxPacket = 512;
    internal const int MaxHops = 16;
    internal const int MaxName = 255;
    internal const int MaxAnswers = 32;
    internal const int TimeoutMs = 3000;
    internal const int TypeA = 1;
    internal const int TypeAaaa = 28;
    internal const int ClassIn = 1;

    internal static Func<string, List<string>> LookupHook;

    internal static void ResetHooks()
    {
        LookupHook = null;
    }

    internal static List<string> ResolveHost(string host, int line, int column)
    {
        if (LookupHook != null) return LookupHook(host);
        return Lookup(host, line, column);
    }

    internal static List<string> Lookup(string host, int line, int column)
    {
        if (!HostOk(host))
            throw new VireError("that name is not valid", line, column);
        List<string> found = new List<string>();
        AddHosts(found, host, ReadOsHosts());
        if (found.Count > 0) return found;
        IPEndPoint[] servers = Nameservers();
        if (servers.Length == 0)
            throw new VireError("could not resolve", line, column);
        byte[] q4 = BuildQuery(host, NewId(), TypeA);
        byte[] q6 = BuildQuery(host, NewId(), TypeAaaa);
        for (int s = 0; s < servers.Length; s++)
        {
            byte[] a4 = ExchangeUdp(servers[s], q4);
            if (a4 != null) ParseResponse(a4, a4.Length, Qid(q4), TypeA, found);
            byte[] a6 = ExchangeUdp(servers[s], q6);
            if (a6 != null) ParseResponse(a6, a6.Length, Qid(q6), TypeAaaa, found);
            if (found.Count > 0) return found;
        }
        throw new VireError("could not resolve", line, column);
    }

    internal static bool HostOk(string host)
    {
        if (string.IsNullOrEmpty(host) || host.Length > MaxName) return false;
        if (host[0] == '.' || host[host.Length - 1] == '.') return false;
        int lab = 0;
        for (int i = 0; i < host.Length; i++)
        {
            char c = host[i];
            if (c == '.')
            {
                if (lab == 0 || lab > 63) return false;
                lab = 0;
                continue;
            }
            bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-';
            if (!ok) return false;
            lab++;
        }
        return lab > 0 && lab <= 63;
    }

    internal static int NewId()
    {
        byte[] b = new byte[2];
        RandomNumberGenerator.Fill(b);
        int id = (b[0] << 8) | b[1];
        if (id == 0) id = 1;
        return id;
    }

    static int Qid(byte[] q)
    {
        if (q == null || q.Length < 2) return 0;
        return (q[0] << 8) | q[1];
    }

    internal static byte[] BuildQuery(string host, int id, int qtype)
    {
        byte[] pkt = new byte[MaxPacket];
        pkt[0] = (byte)((id >> 8) & 255);
        pkt[1] = (byte)(id & 255);
        pkt[2] = 1;
        pkt[3] = 0;
        pkt[4] = 0;
        pkt[5] = 1;
        int off = 12;
        string[] labs = host.Split('.');
        for (int i = 0; i < labs.Length; i++)
        {
            string lab = labs[i];
            if (lab.Length == 0 || lab.Length > 63) return null;
            if (off + 1 + lab.Length + 5 > MaxPacket) return null;
            pkt[off] = (byte)lab.Length;
            off++;
            for (int k = 0; k < lab.Length; k++)
                pkt[off++] = (byte)lab[k];
        }
        pkt[off++] = 0;
        pkt[off++] = (byte)((qtype >> 8) & 255);
        pkt[off++] = (byte)(qtype & 255);
        pkt[off++] = 0;
        pkt[off++] = 1;
        byte[] outp = new byte[off];
        Buffer.BlockCopy(pkt, 0, outp, 0, off);
        return outp;
    }

    internal static int SkipName(byte[] pkt, int len, int off)
    {
        int hops;
        return SkipName(pkt, len, off, out hops);
    }

    internal static int SkipName(byte[] pkt, int len, int off, out int hops)
    {
        hops = 0;
        if (pkt == null || len < 0 || len > pkt.Length) return -1;
        if (off < 0 || off >= len) return -1;
        int pos = off;
        int jumped = 0;
        int endOff = off;
        int name = 0;
        while (true)
        {
            if (pos < 0 || pos >= len) return -1;
            int b = pkt[pos];
            pos++;
            if (b == 0)
            {
                if (jumped == 0) endOff = pos;
                break;
            }
            if ((b & 0xC0) == 0xC0)
            {
                if (pos >= len) return -1;
                int ptr = ((b & 0x3F) << 8) | pkt[pos];
                pos++;
                hops++;
                if (hops > MaxHops) return -1;
                if (ptr < 0 || ptr >= len) return -1;
                if (jumped == 0)
                {
                    endOff = pos;
                    jumped = 1;
                }
                pos = ptr;
                continue;
            }
            if ((b & 0xC0) != 0) return -1;
            name += b + 1;
            if (name > MaxName) return -1;
            if (b > 63) return -1;
            if (pos > len - b) return -1;
            pos += b;
        }
        return jumped != 0 ? endOff : pos;
    }

    internal static bool ParseResponse(byte[] pkt, int len, int wantId, int wantType, List<string> into)
    {
        if (pkt == null || into == null) return false;
        if (len < 12 || len > pkt.Length || len > MaxPacket) return false;
        int id = (pkt[0] << 8) | pkt[1];
        if (id != wantId) return false;
        int flags = (pkt[2] << 8) | pkt[3];
        if ((flags & 0x8000) == 0) return false;
        if ((flags & 0x7800) != 0) return false;
        if ((flags & 0x000F) != 0) return false;
        int qd = (pkt[4] << 8) | pkt[5];
        int an = (pkt[6] << 8) | pkt[7];
        if (qd != 1) return false;
        if (an < 0 || an > MaxAnswers) return false;
        int off = 12;
        off = SkipName(pkt, len, off);
        if (off < 0) return false;
        if (off > len - 4) return false;
        off += 4;
        int n = 0;
        while (n < an)
        {
            off = SkipName(pkt, len, off);
            if (off < 0) return false;
            if (off > len - 10) return false;
            int typ = (pkt[off] << 8) | pkt[off + 1];
            int cls = (pkt[off + 2] << 8) | pkt[off + 3];
            int rdlen = (pkt[off + 8] << 8) | pkt[off + 9];
            off += 10;
            if (rdlen < 0 || off > len - rdlen) return false;
            if (cls == ClassIn && typ == wantType)
            {
                string addr = FormatRdata(pkt, off, rdlen, typ);
                if (addr != null && into.Count < MaxAnswers) into.Add(addr);
            }
            off += rdlen;
            n++;
        }
        return true;
    }

    static string FormatRdata(byte[] pkt, int off, int rdlen, int typ)
    {
        if (typ == TypeA)
        {
            if (rdlen != 4) return null;
            return pkt[off] + "." + pkt[off + 1] + "." + pkt[off + 2] + "." + pkt[off + 3];
        }
        if (typ == TypeAaaa)
        {
            if (rdlen != 16) return null;
            StringBuilder sb = new StringBuilder(39);
            for (int i = 0; i < 16; i += 2)
            {
                if (i > 0) sb.Append(':');
                sb.Append(((pkt[off + i] << 8) | pkt[off + i + 1]).ToString("x"));
            }
            return sb.ToString();
        }
        return null;
    }

    internal static void AddHosts(List<string> found, string host, string text)
    {
        if (string.IsNullOrEmpty(text) || found == null) return;
        string want = host.ToLowerInvariant();
        string[] lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            int hash = line.IndexOf('#');
            if (hash >= 0) line = line.Substring(0, hash);
            line = line.Trim();
            if (line.Length == 0) continue;
            string[] parts = line.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2) continue;
            for (int n = 1; n < parts.Length; n++)
            {
                if (parts[n].ToLowerInvariant() == want)
                {
                    if (found.Count < MaxAnswers) found.Add(parts[0]);
                    break;
                }
            }
        }
    }

    internal static IPEndPoint[] ParseResolv(string text)
    {
        List<IPEndPoint> list = new List<IPEndPoint>();
        if (string.IsNullOrEmpty(text)) return list.ToArray();
        string[] lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i].Trim();
            if (line.Length < 11) continue;
            if (!line.StartsWith("nameserver", StringComparison.Ordinal)) continue;
            string rest = line.Substring(10).Trim();
            IPAddress ip;
            if (!IPAddress.TryParse(rest, out ip)) continue;
            list.Add(new IPEndPoint(ip, 53));
        }
        return list.ToArray();
    }

    static string ReadOsHosts()
    {
        try
        {
            if (OperatingSystem.IsWindows())
                return File.ReadAllText(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "drivers", "etc", "hosts"));
            return File.ReadAllText("/etc/hosts");
        }
        catch (Exception)
        {
            return "";
        }
    }

    static IPEndPoint[] Nameservers()
    {
        string env = Environment.GetEnvironmentVariable("VIRE_DNS");
        if (!string.IsNullOrEmpty(env))
        {
            int colon = env.LastIndexOf(':');
            if (colon > 0)
            {
                IPAddress ip;
                int port;
                if (IPAddress.TryParse(env.Substring(0, colon), out ip) && int.TryParse(env.Substring(colon + 1), out port)
                    && port >= 1 && port <= 65535)
                    return new IPEndPoint[] { new IPEndPoint(ip, port) };
            }
        }
        try
        {
            if (!OperatingSystem.IsWindows())
                return ParseResolv(File.ReadAllText("/etc/resolv.conf"));
        }
        catch (Exception) { }
        return new IPEndPoint[] { new IPEndPoint(IPAddress.Loopback, 53) };
    }

    static byte[] ExchangeUdp(IPEndPoint server, byte[] query)
    {
        if (query == null || server == null) return null;
        using (Socket sock = new Socket(server.AddressFamily, SocketType.Dgram, ProtocolType.Udp))
        {
            try
            {
                sock.ReceiveTimeout = TimeoutMs;
                sock.SendTimeout = TimeoutMs;
                sock.Bind(new IPEndPoint(server.AddressFamily == AddressFamily.InterNetworkV6 ? IPAddress.IPv6Any : IPAddress.Any, 0));
                sock.Connect(server);
                if (sock.Send(query) != query.Length) return null;
                byte[] buf = new byte[MaxPacket];
                int n = sock.Receive(buf);
                if (n <= 0 || n > MaxPacket) return null;
                byte[] got = new byte[n];
                Buffer.BlockCopy(buf, 0, got, 0, n);
                return got;
            }
            catch (Exception)
            {
                return null;
            }
        }
    }
}
