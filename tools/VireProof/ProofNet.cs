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
                }
                s.Flush();
                try { c.Client.Shutdown(SocketShutdown.Send); } catch (Exception) { }
            }
        }
        catch (Exception) { }
    }
}
