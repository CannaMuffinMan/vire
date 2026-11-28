using System;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;

static class ProofPg
{
    const int SslRequestCode = 80877103;

    public static int TlsStub(string pfxPath, string password)
    {
        X509Certificate2 cert = X509CertificateLoader.LoadPkcs12FromFile(pfxPath, password);
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c = l.AcceptTcpClient();
            Thread inner = new Thread(() => ServeTls(c, cert));
            inner.IsBackground = true;
            inner.Start();
        }
    }

    public static int PlainN()
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c = l.AcceptTcpClient();
            Thread inner = new Thread(() =>
            {
                try
                {
                    using (c)
                    {
                        NetworkStream s = c.GetStream();
                        byte[] req = new byte[8];
                        if (!ReadExact(s, req, 8)) return;
                        s.WriteByte((byte)'N');
                        s.Flush();
                    }
                }
                catch (Exception) { }
            });
            inner.IsBackground = true;
            inner.Start();
        }
    }

    static void ServeTls(TcpClient c, X509Certificate2 cert)
    {
        try
        {
            using (c)
            {
                NetworkStream raw = c.GetStream();
                byte[] req = new byte[8];
                if (!ReadExact(raw, req, 8)) return;
                int len = ReadBe32(req, 0);
                int code = ReadBe32(req, 4);
                if (len != 8 || code != SslRequestCode) return;
                raw.WriteByte((byte)'S');
                raw.Flush();
                using (SslStream s = new SslStream(raw, false))
                {
                    s.AuthenticateAsServer(ProofTls.ServerOpts(cert));
                    if (!ReadStartup(s)) return;
                    WriteAll(s, AuthOk());
                    WriteAll(s, ReadyIdle());
                    while (true)
                    {
                        int kind = s.ReadByte();
                        if (kind < 0) return;
                        byte[] hdr = new byte[4];
                        if (!ReadExact(s, hdr, 4)) return;
                        int mlen = ReadBe32(hdr, 0);
                        if (mlen < 4 || mlen > 1000000) return;
                        byte[] body = new byte[mlen - 4];
                        if (body.Length > 0 && !ReadExact(s, body, body.Length)) return;
                        if (kind == (int)'Q')
                        {
                            string sql = CString(body);
                            WriteQuery(s, sql);
                        }
                    }
                }
            }
        }
        catch (Exception) { }
    }

    static bool ReadStartup(Stream s)
    {
        byte[] hdr = new byte[4];
        if (!ReadExact(s, hdr, 4)) return false;
        int len = ReadBe32(hdr, 0);
        if (len < 8 || len > 10000) return false;
        byte[] rest = new byte[len - 4];
        return ReadExact(s, rest, rest.Length);
    }

    static void WriteQuery(Stream s, string sql)
    {
        string text = "1";
        if (sql.IndexOf("42", StringComparison.Ordinal) >= 0) text = "42";
        if (sql.IndexOf("SELECT", StringComparison.OrdinalIgnoreCase) < 0) text = "";
        byte[] name = Encoding.ASCII.GetBytes("?column?\0");
        MemoryStream rd = new MemoryStream();
        WriteBe16(rd, 1);
        rd.Write(name, 0, name.Length);
        WriteBe32(rd, 0);
        WriteBe16(rd, 0);
        WriteBe32(rd, 25);
        WriteBe16(rd, 65535);
        WriteBe32(rd, -1);
        WriteBe16(rd, 0);
        WriteMsg(s, (byte)'T', rd.ToArray());
        byte[] cell = Encoding.ASCII.GetBytes(text);
        MemoryStream dr = new MemoryStream();
        WriteBe16(dr, 1);
        WriteBe32(dr, cell.Length);
        dr.Write(cell, 0, cell.Length);
        WriteMsg(s, (byte)'D', dr.ToArray());
        byte[] cc = Encoding.ASCII.GetBytes("SELECT 1\0");
        WriteMsg(s, (byte)'C', cc);
        WriteAll(s, ReadyIdle());
    }

    static byte[] AuthOk()
    {
        MemoryStream ms = new MemoryStream();
        WriteBe32(ms, 0);
        return Msg((byte)'R', ms.ToArray());
    }

    static byte[] ReadyIdle()
    {
        return Msg((byte)'Z', new byte[] { (byte)'I' });
    }

    static byte[] Msg(byte kind, byte[] body)
    {
        MemoryStream ms = new MemoryStream();
        ms.WriteByte(kind);
        WriteBe32(ms, body.Length + 4);
        ms.Write(body, 0, body.Length);
        return ms.ToArray();
    }

    static void WriteMsg(Stream s, byte kind, byte[] body)
    {
        WriteAll(s, Msg(kind, body));
    }

    static void WriteAll(Stream s, byte[] raw)
    {
        s.Write(raw, 0, raw.Length);
        s.Flush();
    }

    static void WriteBe16(Stream s, int n)
    {
        s.WriteByte((byte)((n >> 8) & 255));
        s.WriteByte((byte)(n & 255));
    }

    static void WriteBe32(Stream s, int n)
    {
        s.WriteByte((byte)((n >> 24) & 255));
        s.WriteByte((byte)((n >> 16) & 255));
        s.WriteByte((byte)((n >> 8) & 255));
        s.WriteByte((byte)(n & 255));
    }

    static int ReadBe32(byte[] b, int i)
    {
        return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    }

    static bool ReadExact(Stream s, byte[] buf, int n)
    {
        int o = 0;
        while (o < n)
        {
            int g = s.Read(buf, o, n - o);
            if (g <= 0) return false;
            o += g;
        }
        return true;
    }

    static string CString(byte[] body)
    {
        int n = body.Length;
        if (n > 0 && body[n - 1] == 0) n--;
        return Encoding.ASCII.GetString(body, 0, n);
    }
}
