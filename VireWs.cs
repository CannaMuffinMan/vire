using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

static class VireWs
{
    public const int MaxPayload = 65536;
    public const int MaxHeader = 8192;
    const string Guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    public static void Listen(int port, int line)
    {
        IPAddress bind = IPAddress.Parse("127.0.0.1");
        TcpListener listener = Bind(bind, port, line);
        IPEndPoint bound = (IPEndPoint)listener.LocalEndpoint;
        if (!IPAddress.IsLoopback(bound.Address) || bound.AddressFamily != AddressFamily.InterNetwork)
        {
            listener.Stop();
            throw new VireError("listener must bind 127.0.0.1", line);
        }
        int actual = bound.Port;
        if (Machine.IsReservedListenPort(actual))
        {
            listener.Stop();
            throw new VireError("that port is reserved", line);
        }
        Console.WriteLine("listening on 127.0.0.1:" + actual);
        try
        {
            while (true)
            {
                TcpClient client;
                try { client = listener.AcceptTcpClient(); }
                catch (SocketException) { continue; }
                catch (ObjectDisposedException) { break; }
                try { Serve(client); }
                catch (IOException) { }
                catch (SocketException) { }
                finally
                {
                    try { client.Close(); } catch (Exception) { }
                }
            }
        }
        finally
        {
            try { listener.Stop(); } catch (Exception) { }
        }
    }

    static TcpListener Bind(IPAddress bind, int port, int line)
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
        throw new VireError("that port is reserved", line);
    }

    static void Serve(TcpClient client)
    {
        NetworkStream stream = client.GetStream();
        stream.ReadTimeout = 10000;
        stream.WriteTimeout = 10000;
        byte[] head = new byte[MaxHeader];
        int got = 0;
        int end = -1;
        while (end < 0 && got < MaxHeader)
        {
            int n;
            try { n = stream.Read(head, got, MaxHeader - got); }
            catch (IOException) { return; }
            if (n <= 0) return;
            got += n;
            end = HeaderEnd(head, got);
        }
        if (end < 0)
        {
            WriteRaw(stream, Encoding.ASCII.GetBytes("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"));
            return;
        }
        string text = Encoding.ASCII.GetString(head, 0, end);
        string key;
        if (!UpgradeOk(text, out key))
        {
            WriteRaw(stream, Encoding.ASCII.GetBytes("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"));
            return;
        }
        string accept = AcceptKey(key);
        string resp = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n";
        WriteRaw(stream, Encoding.ASCII.GetBytes(resp));
        Echo(stream);
    }

    internal static string AcceptKey(string key)
    {
        byte[] dig = SHA1.HashData(Encoding.ASCII.GetBytes(key + Guid));
        return Convert.ToBase64String(dig);
    }

    static bool UpgradeOk(string head, out string key)
    {
        key = null;
        if (head.IndexOf("\nupgrade:", StringComparison.OrdinalIgnoreCase) < 0 &&
            !StartsHeader(head, "upgrade:"))
            return false;
        if (!HeaderHas(head, "upgrade", "websocket")) return false;
        if (!HeaderHas(head, "connection", "upgrade")) return false;
        string ver = HeaderVal(head, "sec-websocket-version");
        if (ver != "13") return false;
        key = HeaderVal(head, "sec-websocket-key");
        if (string.IsNullOrEmpty(key) || key.Length < 16 || key.Length > 32) return false;
        for (int i = 0; i < key.Length; i++)
        {
            char c = key[i];
            if (c < 33 || c > 126) return false;
        }
        return true;
    }

    static bool StartsHeader(string head, string name)
    {
        return head.StartsWith(name, StringComparison.OrdinalIgnoreCase);
    }

    static bool HeaderHas(string head, string name, string token)
    {
        string val = HeaderVal(head, name);
        if (val == null) return false;
        return val.IndexOf(token, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    static string HeaderVal(string head, string name)
    {
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            int colon = line.IndexOf(':');
            if (colon <= 0) continue;
            if (!string.Equals(line.Substring(0, colon).Trim(), name, StringComparison.OrdinalIgnoreCase)) continue;
            return line.Substring(colon + 1).Trim();
        }
        return null;
    }

    static int HeaderEnd(byte[] buf, int n)
    {
        for (int i = 0; i + 3 < n; i++)
        {
            if (buf[i] == 13 && buf[i + 1] == 10 && buf[i + 2] == 13 && buf[i + 3] == 10)
                return i + 4;
        }
        return -1;
    }

    static void Echo(NetworkStream stream)
    {
        List<byte> frag = new List<byte>();
        int fragOp = -1;
        while (true)
        {
            Frame fr;
            try { fr = ReadFrame(stream); }
            catch (WsFail)
            {
                try { WriteFrame(stream, true, 8, new byte[] { 0x03, 0xEA }); } catch (Exception) { }
                return;
            }
            if (fr == null) return;
            if (fr.Op == 8)
            {
                byte[] payload = fr.Payload;
                if (payload.Length == 1) { WriteFrame(stream, true, 8, new byte[] { 0x03, 0xEA }); return; }
                if (payload.Length >= 2)
                {
                    byte[] echo = new byte[Math.Min(payload.Length, 125)];
                    Array.Copy(payload, echo, echo.Length);
                    WriteFrame(stream, true, 8, echo);
                }
                else WriteFrame(stream, true, 8, new byte[0]);
                return;
            }
            if (fr.Op == 9)
            {
                WriteFrame(stream, true, 10, fr.Payload);
                continue;
            }
            if (fr.Op == 10) continue;
            if (fr.Op == 0)
            {
                if (fragOp < 0) throw new WsFail();
                if (frag.Count + fr.Payload.Length > MaxPayload) throw new WsFail();
                frag.AddRange(fr.Payload);
                if (!fr.Fin) continue;
                byte[] all = frag.ToArray();
                if (fragOp == 1 && !Utf8Ok(all)) throw new WsFail();
                WriteFrame(stream, true, fragOp, all);
                frag.Clear();
                fragOp = -1;
                continue;
            }
            if (fr.Op == 1 || fr.Op == 2)
            {
                if (fragOp >= 0) throw new WsFail();
                if (!fr.Fin)
                {
                    fragOp = fr.Op;
                    frag.Clear();
                    frag.AddRange(fr.Payload);
                    continue;
                }
                if (fr.Op == 1 && !Utf8Ok(fr.Payload)) throw new WsFail();
                WriteFrame(stream, true, fr.Op, fr.Payload);
                continue;
            }
            throw new WsFail();
        }
    }

    sealed class Frame
    {
        public bool Fin;
        public int Op;
        public byte[] Payload;
    }

    sealed class WsFail : Exception { }

    static Frame ReadFrame(NetworkStream stream)
    {
        byte[] hdr = ReadExact(stream, 2);
        if (hdr == null) return null;
        int b0 = hdr[0];
        int b1 = hdr[1];
        bool fin = (b0 & 0x80) != 0;
        if ((b0 & 0x70) != 0) throw new WsFail();
        int op = b0 & 0x0f;
        if (op != 0 && op != 1 && op != 2 && op != 8 && op != 9 && op != 10) throw new WsFail();
        if ((b1 & 0x80) == 0) throw new WsFail();
        int len7 = b1 & 0x7f;
        long plen = len7;
        if (len7 == 126)
        {
            byte[] ext = ReadExact(stream, 2);
            if (ext == null) return null;
            plen = (ext[0] << 8) | ext[1];
        }
        else if (len7 == 127)
        {
            byte[] ext = ReadExact(stream, 8);
            if (ext == null) return null;
            if (ext[0] != 0 || ext[1] != 0 || ext[2] != 0 || ext[3] != 0) throw new WsFail();
            plen = ((long)ext[4] << 24) | ((long)ext[5] << 16) | ((long)ext[6] << 8) | ext[7];
            if (plen < 0) throw new WsFail();
        }
        if (plen > MaxPayload) throw new WsFail();
        if (op >= 8)
        {
            if (!fin) throw new WsFail();
            if (plen > 125) throw new WsFail();
        }
        byte[] mask = ReadExact(stream, 4);
        if (mask == null) return null;
        byte[] payload = plen == 0 ? new byte[0] : ReadExact(stream, (int)plen);
        if (payload == null) return null;
        for (int i = 0; i < payload.Length; i++) payload[i] ^= mask[i & 3];
        if (op == 1 && fin && !Utf8Ok(payload)) throw new WsFail();
        Frame fr = new Frame();
        fr.Fin = fin;
        fr.Op = op;
        fr.Payload = payload;
        return fr;
    }

    static byte[] ReadExact(NetworkStream stream, int n)
    {
        byte[] buf = new byte[n];
        int got = 0;
        while (got < n)
        {
            int r;
            try { r = stream.Read(buf, got, n - got); }
            catch (IOException) { return null; }
            if (r <= 0) return null;
            got += r;
        }
        return buf;
    }

    static void WriteFrame(NetworkStream stream, bool fin, int op, byte[] payload)
    {
        if (payload == null) payload = new byte[0];
        if (payload.Length > MaxPayload) throw new WsFail();
        int extra = payload.Length < 126 ? 0 : payload.Length < 65536 ? 2 : 8;
        byte[] buf = new byte[2 + extra + payload.Length];
        buf[0] = (byte)((fin ? 0x80 : 0) | (op & 0x0f));
        if (payload.Length < 126) buf[1] = (byte)payload.Length;
        else if (payload.Length < 65536)
        {
            buf[1] = 126;
            buf[2] = (byte)(payload.Length >> 8);
            buf[3] = (byte)payload.Length;
        }
        else
        {
            buf[1] = 127;
            buf[9] = (byte)payload.Length;
            buf[8] = (byte)(payload.Length >> 8);
            buf[7] = (byte)(payload.Length >> 16);
            buf[6] = (byte)(payload.Length >> 24);
        }
        Buffer.BlockCopy(payload, 0, buf, 2 + extra, payload.Length);
        WriteRaw(stream, buf);
    }

    static void WriteRaw(NetworkStream stream, byte[] data)
    {
        stream.Write(data, 0, data.Length);
    }

    static bool Utf8Ok(byte[] buf)
    {
        try
        {
            Encoding enc = new UTF8Encoding(false, true);
            enc.GetString(buf);
            return true;
        }
        catch (DecoderFallbackException) { return false; }
        catch (ArgumentException) { return false; }
    }
}
