using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

static class ProofNet
{
    const string WsGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    public static int DnsStub(string mapPath)
    {
        using (UdpClient udp = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0)))
        {
            int port = ((IPEndPoint)udp.Client.LocalEndPoint).Port;
            byte[] map = Encoding.ASCII.GetBytes("127.0.0.1 " + port + "\n");
            using (FileStream created = new FileStream(mapPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
            {
                created.Write(map, 0, map.Length);
                created.Flush(true);
            }
            // Keep a shared read handle (not write) so PE CreateFileA FILE_SHARE_READ
            // can still open data/vire-dns and exercise dns_ns_scan / rbx.
            using (FileStream hold = new FileStream(mapPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                Console.WriteLine("dns_stub 127.0.0.1:" + port);
                Console.Out.Flush();
                while (true)
                {
                    IPEndPoint ep = new IPEndPoint(IPAddress.Any, 0);
                    byte[] req;
                    try { req = udp.Receive(ref ep); }
                    catch (SocketException) { break; }
                    if (req == null || req.Length < 12) continue;
                    byte[] ans = new byte[req.Length + 16];
                    Buffer.BlockCopy(req, 0, ans, 0, req.Length);
                    ans[2] = 0x81;
                    ans[3] = 0x80;
                    ans[7] = 1;
                    byte[] rr = new byte[] { 0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 0, 0, 4, 127, 0, 0, 1 };
                    Buffer.BlockCopy(rr, 0, ans, req.Length, rr.Length);
                    udp.Send(ans, ans.Length, ep);
                }
            }
        }
        return 0;
    }

    public static int HttpEcho()
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.WriteLine("upstream 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c;
            try { c = l.AcceptTcpClient(); }
            catch (SocketException) { break; }
            Thread t = new Thread(() => ServeEcho(c));
            t.IsBackground = true;
            t.Start();
        }
        return 0;
    }

    static void ServeEcho(TcpClient c)
    {
        try
        {
            using (c)
            {
                c.ReceiveTimeout = 8000;
                NetworkStream s = c.GetStream();
                MemoryStream ms = new MemoryStream();
                byte[] buf = new byte[4096];
                int n;
                try { n = s.Read(buf, 0, buf.Length); }
                catch (Exception) { return; }
                if (n <= 0) return;
                ms.Write(buf, 0, n);
                byte[] data = ms.ToArray();
                string text = Encoding.ASCII.GetString(data);
                int split = text.IndexOf("\r\n\r\n");
                string start = split >= 0 ? text.Substring(0, split) : text;
                string[] lines = start.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                string req = lines.Length > 0 ? lines[0] : "";
                string[] parts = req.Split(' ');
                string method = parts.Length > 0 ? parts[0] : "GET";
                string path = parts.Length > 1 ? parts[1] : "/";
                byte[] body = new byte[0];
                if (method == "POST" && split >= 0)
                {
                    int cl = 0;
                    for (int i = 1; i < lines.Length; i++)
                    {
                        if (lines[i].StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                            int.TryParse(lines[i].Substring(15).Trim(), out cl);
                    }
                    byte[] rest = new byte[data.Length - (split + 4)];
                    Buffer.BlockCopy(data, split + 4, rest, 0, rest.Length);
                    while (rest.Length < cl)
                    {
                        n = s.Read(buf, 0, buf.Length);
                        if (n <= 0) break;
                        byte[] next = new byte[rest.Length + n];
                        Buffer.BlockCopy(rest, 0, next, 0, rest.Length);
                        Buffer.BlockCopy(buf, 0, next, rest.Length, n);
                        rest = next;
                    }
                    body = new byte[Math.Min(cl, rest.Length)];
                    Buffer.BlockCopy(rest, 0, body, 0, body.Length);
                }
                byte[] payload;
                if (path.StartsWith("/hang", StringComparison.Ordinal))
                {
                    Thread.Sleep(8000);
                    return;
                }
                if (path.StartsWith("/chunk", StringComparison.Ordinal))
                    payload = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n");
                else if (path.StartsWith("/clte", StringComparison.Ordinal))
                    payload = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\nabcd");
                else if (path.StartsWith("/dupcl", StringComparison.Ordinal))
                    payload = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab");
                else if (path.StartsWith("/oversize", StringComparison.Ordinal))
                {
                    byte[] head = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 1000001\r\n\r\n");
                    payload = new byte[head.Length + 64];
                    Buffer.BlockCopy(head, 0, payload, 0, head.Length);
                    for (int i = head.Length; i < payload.Length; i++) payload[i] = (byte)'x';
                }
                else if (path.StartsWith("/redir", StringComparison.Ordinal))
                    payload = Encoding.ASCII.GetBytes("HTTP/1.1 307 Error\r\nLocation: /sop\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                else if (path.StartsWith("/echo", StringComparison.Ordinal))
                {
                    byte[] msg = method == "POST"
                        ? Concat(Encoding.ASCII.GetBytes("echo-post:"), body)
                        : Encoding.ASCII.GetBytes("echo-get");
                    payload = WrapBody(200, "text/plain", msg, "X-Keep: yes\r\n");
                }
                else if (path.StartsWith("/up", StringComparison.Ordinal))
                {
                    byte[] msg = method == "POST" && body.Length > 0 ? body : Encoding.ASCII.GetBytes("up-ok");
                    payload = WrapBody(200, "text/plain", msg, "");
                }
                else
                    payload = Encoding.ASCII.GetBytes("HTTP/1.1 404 Error\r\nContent-Length: 0\r\n\r\n");
                s.Write(payload, 0, payload.Length);
                s.Flush();
            }
        }
        catch (Exception) { }
    }

    static byte[] Concat(byte[] a, byte[] b)
    {
        byte[] outb = new byte[a.Length + b.Length];
        Buffer.BlockCopy(a, 0, outb, 0, a.Length);
        Buffer.BlockCopy(b, 0, outb, a.Length, b.Length);
        return outb;
    }

    static byte[] WrapBody(int status, string ctype, byte[] msg, string extra)
    {
        string head = "HTTP/1.1 " + status + " OK\r\nContent-Type: " + ctype + "\r\n" + extra
            + "Connection: close\r\nContent-Length: " + msg.Length + "\r\n\r\n";
        return Concat(Encoding.ASCII.GetBytes(head), msg);
    }

    public static int HttpUpOk()
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.WriteLine("upstream 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c;
            try { c = l.AcceptTcpClient(); }
            catch (SocketException) { break; }
            Thread t = new Thread(() => ServeUpOk(c));
            t.IsBackground = true;
            t.Start();
        }
        return 0;
    }

    static void ServeUpOk(TcpClient c)
    {
        try
        {
            using (c)
            {
                c.Client.LingerState = new LingerOption(true, 2);
                NetworkStream s = c.GetStream();
                byte[] buf = new byte[4096];
                try { s.Read(buf, 0, buf.Length); } catch (Exception) { }
                byte[] payload = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\nConnection: close\r\n\r\nup-ok");
                s.Write(payload, 0, payload.Length);
                s.Flush();
                try { c.Client.Shutdown(SocketShutdown.Send); } catch (Exception) { }
            }
        }
        catch (Exception) { }
    }

    public static int WsUpstream()
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.WriteLine("upstream 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c;
            try { c = l.AcceptTcpClient(); }
            catch (SocketException) { break; }
            Thread t = new Thread(() => ServeWs(c));
            t.IsBackground = true;
            t.Start();
        }
        return 0;
    }

    static void ServeWs(TcpClient c)
    {
        try
        {
            using (c)
            {
                c.Client.LingerState = new LingerOption(true, 2);
                NetworkStream s = c.GetStream();
                s.ReadTimeout = 5000;
                byte[] buf = new byte[16384];
                int n = s.Read(buf, 0, buf.Length);
                string text = Encoding.ASCII.GetString(buf, 0, n);
                byte[] resp;
                if (text.IndexOf("/ws/refuse", StringComparison.Ordinal) >= 0)
                {
                    byte[] body = Encoding.ASCII.GetBytes("forbidden");
                    resp = Encoding.ASCII.GetBytes("HTTP/1.1 403 Forbidden\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
                    s.Write(resp, 0, resp.Length);
                    s.Write(body, 0, body.Length);
                }
                else if (text.IndexOf("Upgrade: websocket", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    resp = Encoding.ASCII.GetBytes("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    s.Write(resp, 0, resp.Length);
                }
                else
                {
                    string key = "";
                    string[] lines = text.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                    for (int i = 0; i < lines.Length; i++)
                    {
                        if (lines[i].StartsWith("Sec-WebSocket-Key:", StringComparison.OrdinalIgnoreCase))
                            key = lines[i].Substring(18).Trim();
                    }
                    string accept;
                    using (SHA1 sha = SHA1.Create())
                    {
                        accept = Convert.ToBase64String(sha.ComputeHash(Encoding.ASCII.GetBytes(key + WsGuid)));
                    }
                    resp = Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n");
                    s.Write(resp, 0, resp.Length);
                    EchoWsFrames(s);
                }
                s.Flush();
                try { c.Client.Shutdown(SocketShutdown.Send); } catch (Exception) { }
            }
        }
        catch (Exception) { }
    }

    static void EchoWsFrames(NetworkStream s)
    {
        byte[] hold = new byte[0];
        while (true)
        {
            byte[] two = ReadExact(s, ref hold, 2);
            if (two == null) return;
            int op = two[0] & 0x0F;
            bool masked = (two[1] & 0x80) != 0;
            int ln = two[1] & 0x7F;
            if (ln == 126)
            {
                byte[] ext = ReadExact(s, ref hold, 2);
                if (ext == null) return;
                ln = (ext[0] << 8) | ext[1];
            }
            else if (ln == 127) return;
            byte[] mask = masked ? ReadExact(s, ref hold, 4) : new byte[0];
            if (masked && mask == null) return;
            byte[] payload = ReadExact(s, ref hold, ln);
            if (payload == null) return;
            if (masked)
            {
                for (int i = 0; i < payload.Length; i++)
                    payload[i] = (byte)(payload[i] ^ mask[i & 3]);
            }
            if (op == 8)
            {
                s.Write(new byte[] { 0x88, 0x00 }, 0, 2);
                return;
            }
            if (op == 9)
            {
                byte[] pong = new byte[2 + payload.Length];
                pong[0] = 0x8A;
                pong[1] = (byte)payload.Length;
                Buffer.BlockCopy(payload, 0, pong, 2, payload.Length);
                s.Write(pong, 0, pong.Length);
                continue;
            }
            if (op == 1 || op == 2)
            {
                byte[] frame = new byte[2 + payload.Length];
                frame[0] = (byte)(0x80 | op);
                frame[1] = (byte)payload.Length;
                Buffer.BlockCopy(payload, 0, frame, 2, payload.Length);
                s.Write(frame, 0, frame.Length);
            }
        }
    }

    static byte[] ReadExact(NetworkStream s, ref byte[] hold, int n)
    {
        while (hold.Length < n)
        {
            byte[] buf = new byte[4096];
            int got;
            try { got = s.Read(buf, 0, buf.Length); }
            catch (Exception) { return null; }
            if (got <= 0) return null;
            byte[] next = new byte[hold.Length + got];
            Buffer.BlockCopy(hold, 0, next, 0, hold.Length);
            Buffer.BlockCopy(buf, 0, next, hold.Length, got);
            hold = next;
        }
        byte[] take = new byte[n];
        Buffer.BlockCopy(hold, 0, take, 0, n);
        byte[] rest = new byte[hold.Length - n];
        Buffer.BlockCopy(hold, n, rest, 0, rest.Length);
        hold = rest;
        return take;
    }

    public static int WsProve(int port)
    {
        TcpClient tcp = new TcpClient();
        tcp.Connect(IPAddress.Loopback, port);
        NetworkStream s = tcp.GetStream();
        s.ReadTimeout = 4000;
        s.WriteTimeout = 4000;
        string key = Convert.ToBase64String(Encoding.ASCII.GetBytes("0123456789abcdef"));
        byte[] req = Encoding.ASCII.GetBytes(
            "GET /ws/kick HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: "
            + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n");
        s.Write(req, 0, req.Length);
        byte[] buf = new byte[4096];
        int n = s.Read(buf, 0, buf.Length);
        string head = Encoding.ASCII.GetString(buf, 0, n);
        if (head.IndexOf("101", StringComparison.Ordinal) < 0)
            throw new InvalidOperationException("no 101: " + head);
        byte[] mask = new byte[] { 0x37, 0xfa, 0x21, 0x3d };
        byte[] payload = Encoding.ASCII.GetBytes("xyz");
        byte[] frame = new byte[6 + payload.Length];
        frame[0] = 0x81;
        frame[1] = (byte)(0x80 | payload.Length);
        Buffer.BlockCopy(mask, 0, frame, 2, 4);
        for (int i = 0; i < payload.Length; i++)
            frame[6 + i] = (byte)(payload[i] ^ mask[i & 3]);
        s.Write(frame, 0, frame.Length);
        n = s.Read(buf, 0, buf.Length);
        if (n < 5 || buf[0] != 0x81 || buf[1] != 0x03 || buf[2] != (byte)'x')
            throw new InvalidOperationException("echo mismatch");
        Console.WriteLine("ws_prove_ok 101 echo xyz");
        tcp.Close();
        return 0;
    }
}
