using System;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;

static class ProofPg
{
    static byte[] Be32(int n)
    {
        return new byte[] { (byte)(n >> 24), (byte)(n >> 16), (byte)(n >> 8), (byte)n };
    }

    static byte[] AuthSasl()
    {
        byte[] plus = Encoding.ASCII.GetBytes("SCRAM-SHA-256-PLUS");
        byte[] plain = Encoding.ASCII.GetBytes("SCRAM-SHA-256");
        using (MemoryStream body = new MemoryStream())
        {
            body.Write(Be32(10), 0, 4);
            body.Write(plus, 0, plus.Length);
            body.WriteByte(0);
            body.Write(plain, 0, plain.Length);
            body.WriteByte(0);
            body.WriteByte(0);
            byte[] payload = body.ToArray();
            using (MemoryStream msg = new MemoryStream())
            {
                msg.WriteByte((byte)'R');
                msg.Write(Be32(payload.Length + 4), 0, 4);
                msg.Write(payload, 0, payload.Length);
                return msg.ToArray();
            }
        }
    }

    static byte[] AuthContinue(string payload)
    {
        byte[] raw = Encoding.ASCII.GetBytes(payload);
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            msg.Write(Be32(4 + 4 + raw.Length), 0, 4);
            msg.Write(Be32(11), 0, 4);
            msg.Write(raw, 0, raw.Length);
            return msg.ToArray();
        }
    }

    static byte[] AuthFinalError(string e)
    {
        byte[] payload = Encoding.ASCII.GetBytes("e=" + e);
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            msg.Write(Be32(4 + 4 + payload.Length), 0, 4);
            msg.Write(Be32(12), 0, 4);
            msg.Write(payload, 0, payload.Length);
            return msg.ToArray();
        }
    }

    static byte[] AuthFinalOk(string v)
    {
        byte[] payload = Encoding.ASCII.GetBytes("v=" + v);
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            msg.Write(Be32(4 + 4 + payload.Length), 0, 4);
            msg.Write(Be32(12), 0, 4);
            msg.Write(payload, 0, payload.Length);
            return msg.ToArray();
        }
    }

    static byte[] AuthOk()
    {
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            msg.Write(Be32(8), 0, 4);
            msg.Write(Be32(0), 0, 4);
            return msg.ToArray();
        }
    }

    static byte[] Ready()
    {
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'Z');
            msg.Write(Be32(5), 0, 4);
            msg.WriteByte((byte)'I');
            return msg.ToArray();
        }
    }

    static string ServerSig(string secret, string saltB64, int rounds, string bare, string serverFirst, string without)
    {
        byte[] salt = Convert.FromBase64String(saltB64);
        byte[] salted = Rfc2898DeriveBytes.Pbkdf2(secret, salt, rounds, HashAlgorithmName.SHA256, 32);
        byte[] serverKey = HMACSHA256.HashData(salted, Encoding.ASCII.GetBytes("Server Key"));
        byte[] auth = Encoding.ASCII.GetBytes(bare + "," + serverFirst + "," + without);
        return Convert.ToBase64String(HMACSHA256.HashData(serverKey, auth));
    }

    public static int TlsStub(string pfxPath, string password, string mode)
    {
        bool mitm = mode == "mitm";
        X509Certificate2 cert = X509CertificateLoader.LoadPkcs12FromFile(pfxPath, password);
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c = l.AcceptTcpClient();
            Thread inner = new Thread(() => Serve(c, cert, mitm));
            inner.IsBackground = true;
            inner.Start();
        }
    }

    static void Serve(TcpClient c, X509Certificate2 cert, bool mitm)
    {
        try
        {
            using (c)
            using (NetworkStream raw = c.GetStream())
            {
                raw.ReadTimeout = 8000;
                raw.WriteTimeout = 8000;
                byte[] buf = new byte[16384];
                int n = raw.Read(buf, 0, 8);
                if (n < 8) return;
                raw.WriteByte((byte)'S');
                using (SslStream ssl = new SslStream(raw, false))
                {
                    ssl.AuthenticateAsServer(new SslServerAuthenticationOptions
                    {
                        ServerCertificate = cert,
                        EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13,
                        CertificateRevocationCheckMode = X509RevocationMode.NoCheck
                    });
                    ssl.Read(buf, 0, buf.Length);
                    byte[] sasl = AuthSasl();
                    ssl.Write(sasl, 0, sasl.Length);
                    n = ssl.Read(buf, 0, buf.Length);
                    if (n < 1) return;
                    string captured = Encoding.Latin1.GetString(buf, 0, n);
                    int rAt = captured.IndexOf(",r=", StringComparison.Ordinal);
                    if (rAt < 0) return;
                    string cn = captured.Substring(rAt + 3).TrimEnd('\0');
                    int z = cn.IndexOf('\0');
                    if (z >= 0) cn = cn.Substring(0, z);
                    string sn = cn + "s";
                    string sf = "r=" + sn + ",s=W22ZaJ0SNY7soEsUEjb6gQ==,i=2";
                    byte[] cont = AuthContinue(sf);
                    ssl.Write(cont, 0, cont.Length);
                    n = ssl.Read(buf, 0, buf.Length);
                    if (n < 1) return;
                    string clientFinal = Encoding.Latin1.GetString(buf, 0, n);
                    if (mitm)
                    {
                        byte[] err = AuthFinalError("channel binding");
                        ssl.Write(err, 0, err.Length);
                        try { ssl.Read(buf, 0, buf.Length); } catch (IOException) { }
                        return;
                    }
                    int pAt = captured.IndexOf("n=user,r=", StringComparison.Ordinal);
                    string bare = pAt >= 0 ? captured.Substring(pAt).TrimEnd('\0') : "";
                    int comma = clientFinal.LastIndexOf(",p=", StringComparison.Ordinal);
                    string without = "";
                    if (comma > 0)
                    {
                        int cAt = clientFinal.IndexOf("c=", StringComparison.Ordinal);
                        if (cAt >= 0) without = clientFinal.Substring(cAt, comma - cAt);
                    }
                    string v = ServerSig("pencil", "W22ZaJ0SNY7soEsUEjb6gQ==", 2, bare, sf, without);
                    byte[] fin = AuthFinalOk(v);
                    ssl.Write(fin, 0, fin.Length);
                    byte[] ok = AuthOk();
                    ssl.Write(ok, 0, ok.Length);
                    byte[] ready = Ready();
                    ssl.Write(ready, 0, ready.Length);
                    try { ssl.Read(buf, 0, buf.Length); } catch (IOException) { }
                }
            }
        }
        catch (Exception) { }
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

    static bool ReadExact(Stream s, byte[] buf, int n)
    {
        int off = 0;
        while (off < n)
        {
            int got = s.Read(buf, off, n - off);
            if (got <= 0) return false;
            off += got;
        }
        return true;
    }
}
