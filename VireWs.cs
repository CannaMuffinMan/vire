using System;
using System.IO;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

static class VireWs
{
    public const int PayloadCap = 65536;
    const string Guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    public static bool IsUpgradeGet(HttpWire.Result headers)
    {
        if (headers == null || headers.Status != 0) return false;
        if (!string.Equals(headers.Method, "GET", StringComparison.Ordinal)) return false;
        string upgrade = HeaderValue(headers.Head, "upgrade");
        if (!ContainsToken(upgrade, "websocket")) return false;
        string connection = HeaderValue(headers.Head, "connection");
        if (!ContainsToken(connection, "upgrade")) return false;
        string version = HeaderValue(headers.Head, "sec-websocket-version");
        if (version == null || !version.StartsWith("13", StringComparison.Ordinal)) return false;
        string key = HeaderValue(headers.Head, "sec-websocket-key");
        return key != null && key.Length > 0;
    }

    public static bool IsLivePath(string path)
    {
        if (path == null) return false;
        if (path == "/chat" || path == "/live") return true;
        if (path == "/ws/chat" || path == "/ws/live" || path == "/ws/kick") return true;
        return path.StartsWith("/ws/", StringComparison.Ordinal);
    }

    public static void Answer(Stream stream, HttpWire.Result headers)
    {
        if (!IsUpgradeGet(headers))
        {
            byte[] bad = Encoding.ASCII.GetBytes("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
            stream.Write(bad, 0, bad.Length);
            return;
        }
        string key = HeaderValue(headers.Head, "sec-websocket-key");
        string accept = AcceptOf(key);
        string head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "
            + accept + "\r\n\r\n";
        byte[] prefix = Encoding.ASCII.GetBytes(head);
        stream.Write(prefix, 0, prefix.Length);
        try { stream.Flush(); } catch (IOException) { }
        Echo(stream);
    }

    static string AcceptOf(string key)
    {
        byte[] digest = SHA1.HashData(Encoding.ASCII.GetBytes(key + Guid));
        return Convert.ToBase64String(digest);
    }

    static void Echo(Stream stream)
    {
        byte[] assembled = new byte[PayloadCap];
        int assembledLen = 0;
        int fragOp = -1;
        int closeCode = 0;
        while (true)
        {
            int op;
            bool fin;
            byte[] payload;
            if (!ReadFrame(stream, out op, out fin, out payload, ref closeCode))
            {
                if (closeCode == 0) closeCode = 1002;
                WriteClose(stream, closeCode);
                return;
            }
            if (op == 8)
            {
                WriteFrame(stream, 8, payload);
                return;
            }
            if (op == 9)
            {
                WriteFrame(stream, 10, payload);
                continue;
            }
            if (op == 10) continue;
            if (op == 0)
            {
                if (fragOp < 0) { WriteClose(stream, 1002); return; }
                if (assembledLen + payload.Length > PayloadCap) { WriteClose(stream, 1009); return; }
                Buffer.BlockCopy(payload, 0, assembled, assembledLen, payload.Length);
                assembledLen += payload.Length;
                if (!fin) continue;
                byte[] full = new byte[assembledLen];
                Buffer.BlockCopy(assembled, 0, full, 0, assembledLen);
                WriteFrame(stream, fragOp, full);
                fragOp = -1;
                assembledLen = 0;
                continue;
            }
            if (op != 1 && op != 2) { WriteClose(stream, 1002); return; }
            if (fragOp >= 0) { WriteClose(stream, 1002); return; }
            if (!fin)
            {
                if (payload.Length > PayloadCap) { WriteClose(stream, 1009); return; }
                Buffer.BlockCopy(payload, 0, assembled, 0, payload.Length);
                assembledLen = payload.Length;
                fragOp = op;
                continue;
            }
            WriteFrame(stream, op, payload);
        }
    }

    static bool ReadFrame(Stream stream, out int op, out bool fin, out byte[] payload, ref int closeCode)
    {
        op = 0;
        fin = false;
        payload = Array.Empty<byte>();
        byte[] hdr = new byte[2];
        if (!ReadExact(stream, hdr, 0, 2)) return false;
        int b0 = hdr[0];
        int b1 = hdr[1];
        if ((b0 & 0x70) != 0) { closeCode = 1002; return false; }
        fin = (b0 & 0x80) != 0;
        op = b0 & 0x0f;
        if ((b1 & 0x80) == 0) { closeCode = 1002; return false; }
        long len = b1 & 0x7f;
        if (len == 126)
        {
            byte[] ext = new byte[2];
            if (!ReadExact(stream, ext, 0, 2)) return false;
            len = (ext[0] << 8) | ext[1];
            if (len < 126) { closeCode = 1002; return false; }
        }
        else if (len == 127)
        {
            byte[] ext = new byte[8];
            if (!ReadExact(stream, ext, 0, 8)) return false;
            if (ext[0] != 0 || ext[1] != 0 || ext[2] != 0 || ext[3] != 0) { closeCode = 1002; return false; }
            len = ((long)ext[4] << 24) | ((long)ext[5] << 16) | ((long)ext[6] << 8) | ext[7];
            if (len < PayloadCap) { closeCode = 1009; return false; }
        }
        if (len > PayloadCap) { closeCode = 1009; return false; }
        if (op >= 8)
        {
            if (!fin) { closeCode = 1002; return false; }
            if (len > 125) { closeCode = 1002; return false; }
        }
        byte[] mask = new byte[4];
        if (!ReadExact(stream, mask, 0, 4)) return false;
        payload = new byte[(int)len];
        if (len > 0 && !ReadExact(stream, payload, 0, (int)len)) return false;
        for (int i = 0; i < payload.Length; i++) payload[i] ^= mask[i & 3];
        return true;
    }

    static void WriteFrame(Stream stream, int op, byte[] payload)
    {
        if (payload == null) payload = Array.Empty<byte>();
        if (payload.Length > PayloadCap) return;
        byte[] hdr;
        if (payload.Length < 126)
        {
            hdr = new byte[2];
            hdr[0] = (byte)(0x80 | (op & 0x0f));
            hdr[1] = (byte)payload.Length;
        }
        else
        {
            hdr = new byte[4];
            hdr[0] = (byte)(0x80 | (op & 0x0f));
            hdr[1] = 126;
            hdr[2] = (byte)((payload.Length >> 8) & 0xff);
            hdr[3] = (byte)(payload.Length & 0xff);
        }
        stream.Write(hdr, 0, hdr.Length);
        if (payload.Length > 0) stream.Write(payload, 0, payload.Length);
        try { stream.Flush(); } catch (IOException) { }
    }

    static void WriteClose(Stream stream, int code)
    {
        byte[] payload = new byte[2];
        payload[0] = (byte)((code >> 8) & 0xff);
        payload[1] = (byte)(code & 0xff);
        try { WriteFrame(stream, 8, payload); }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
        catch (SocketException) { }
    }

    static bool ReadExact(Stream stream, byte[] buffer, int offset, int count)
    {
        int got = 0;
        while (got < count)
        {
            int n;
            try
            {
                stream.ReadTimeout = 5000;
                n = stream.Read(buffer, offset + got, count - got);
            }
            catch (IOException) { return false; }
            if (n <= 0) return false;
            got += n;
        }
        return true;
    }

    static string HeaderValue(string head, string name)
    {
        if (head == null) return null;
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        for (int i = 1; i < lines.Length; i++)
        {
            string line = lines[i];
            int colon = line.IndexOf(':');
            if (colon <= 0) continue;
            string got = line.Substring(0, colon).Trim();
            if (!string.Equals(got, name, StringComparison.OrdinalIgnoreCase)) continue;
            return line.Substring(colon + 1).Trim();
        }
        return null;
    }

    static bool ContainsToken(string value, string token)
    {
        if (value == null || token == null) return false;
        string[] parts = value.Split(new char[] { ',', ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
        for (int i = 0; i < parts.Length; i++)
        {
            if (string.Equals(parts[i], token, StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }
}
