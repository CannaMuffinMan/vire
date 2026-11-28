using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;

static class ProofRedis
{
    public static int TlsStub(string pfxPath, string password, string expiredPfx, string expiredPassword)
    {
        X509Certificate2 cert = X509CertificateLoader.LoadPkcs12FromFile(pfxPath, password);
        X509Certificate2 expired = X509CertificateLoader.LoadPkcs12FromFile(expiredPfx, expiredPassword);
        TcpListener tls = Listen();
        TcpListener plain = Listen();
        TcpListener exp = Listen();
        Console.WriteLine("listening on 127.0.0.1:" + ((IPEndPoint)tls.LocalEndpoint).Port);
        Console.WriteLine("listening-plain on 127.0.0.1:" + ((IPEndPoint)plain.LocalEndpoint).Port);
        Console.WriteLine("listening-expired on 127.0.0.1:" + ((IPEndPoint)exp.LocalEndpoint).Port);
        Console.Out.Flush();
        AcceptLoop(tls, c => ServeTls(c, cert));
        AcceptLoop(plain, ServePlain);
        AcceptLoop(exp, c => ServeTls(c, expired));
        while (true) Thread.Sleep(60000);
    }

    static TcpListener Listen()
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        return l;
    }

    static void AcceptLoop(TcpListener l, Action<TcpClient> serve)
    {
        Thread t = new Thread(() =>
        {
            while (true)
            {
                TcpClient c = l.AcceptTcpClient();
                Thread inner = new Thread(() => serve(c));
                inner.IsBackground = true;
                inner.Start();
            }
        });
        t.IsBackground = true;
        t.Start();
    }

    static void ServePlain(TcpClient c)
    {
        try
        {
            using (c)
            {
                NetworkStream s = c.GetStream();
                byte[] buf = new byte[256];
                s.Read(buf, 0, buf.Length);
            }
        }
        catch (Exception) { }
    }

    static void ServeTls(TcpClient c, X509Certificate2 cert)
    {
        Dictionary<string, string> store = new Dictionary<string, string>();
        try
        {
            using (c)
            using (SslStream s = new SslStream(c.GetStream(), false))
            {
                s.AuthenticateAsServer(ProofTls.ServerOpts(cert));
                StringBuilder buf = new StringBuilder();
                byte[] tmp = new byte[4096];
                while (true)
                {
                    int n = s.Read(tmp, 0, tmp.Length);
                    if (n <= 0) return;
                    buf.Append(Encoding.ASCII.GetString(tmp, 0, n));
                    while (TryCmd(buf, out List<string> parts))
                    {
                        string reply = Dispatch(parts, store);
                        byte[] raw = Encoding.ASCII.GetBytes(reply);
                        s.Write(raw, 0, raw.Length);
                        s.Flush();
                    }
                }
            }
        }
        catch (Exception) { }
    }

    static string Dispatch(List<string> parts, Dictionary<string, string> store)
    {
        if (parts.Count < 1) return "-ERR empty\r\n";
        string cmd = parts[0].ToUpperInvariant();
        if (cmd == "AUTH") return "+OK\r\n";
        if (cmd == "PING") return "+PONG\r\n";
        if (cmd == "SET" && parts.Count >= 3)
        {
            store[parts[1]] = parts[2];
            return "+OK\r\n";
        }
        if (cmd == "GET" && parts.Count >= 2)
        {
            string v;
            if (!store.TryGetValue(parts[1], out v)) return "$-1\r\n";
            return "$" + v.Length + "\r\n" + v + "\r\n";
        }
        return "-ERR unknown\r\n";
    }

    static bool TryCmd(StringBuilder buf, out List<string> parts)
    {
        parts = null;
        string text = buf.ToString();
        if (text.Length < 4 || text[0] != '*') return false;
        int nl = text.IndexOf("\r\n", StringComparison.Ordinal);
        if (nl < 0) return false;
        int argc;
        if (!int.TryParse(text.Substring(1, nl - 1), out argc)) return false;
        int i = nl + 2;
        parts = new List<string>();
        for (int a = 0; a < argc; a++)
        {
            if (i >= text.Length || text[i] != '$') return false;
            int n2 = text.IndexOf("\r\n", i, StringComparison.Ordinal);
            if (n2 < 0) { parts = null; return false; }
            int ln;
            if (!int.TryParse(text.Substring(i + 1, n2 - i - 1), out ln)) { parts = null; return false; }
            int start = n2 + 2;
            if (start + ln + 2 > text.Length) { parts = null; return false; }
            parts.Add(text.Substring(start, ln));
            i = start + ln + 2;
        }
        buf.Remove(0, i);
        return true;
    }
}
