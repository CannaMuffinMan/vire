using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

static class ProofTls
{
    static string Pem(string type, byte[] der)
    {
        return "-----BEGIN " + type + "-----\n"
            + Convert.ToBase64String(der, Base64FormattingOptions.InsertLineBreaks)
            + "\n-----END " + type + "-----\n";
    }

    static X509Certificate2 MakeCert(RSA rsa)
    {
        CertificateRequest req = new CertificateRequest("CN=localhost", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        SubjectAlternativeNameBuilder san = new SubjectAlternativeNameBuilder();
        san.AddDnsName("localhost");
        san.AddIpAddress(IPAddress.Loopback);
        req.CertificateExtensions.Add(san.Build());
        return req.CreateSelfSigned(DateTimeOffset.UtcNow.AddHours(-1), DateTimeOffset.UtcNow.AddDays(7));
    }

    public static void WritePem(string certPath, string keyPath)
    {
        using (RSA rsa = RSA.Create(2048))
        using (X509Certificate2 cert = MakeCert(rsa))
        {
            File.WriteAllText(certPath, Pem("CERTIFICATE", cert.Export(X509ContentType.Cert)));
            File.WriteAllText(keyPath, Pem("RSA PRIVATE KEY", rsa.ExportRSAPrivateKey()));
        }
    }

    public static void WritePfx(string pfxPath, string cerPath, string password)
    {
        using (RSA rsa = RSA.Create(2048))
        using (X509Certificate2 cert = MakeCert(rsa))
        {
            File.WriteAllBytes(pfxPath, cert.Export(X509ContentType.Pfx, password ?? ""));
            File.WriteAllText(cerPath, Pem("CERTIFICATE", cert.Export(X509ContentType.Cert)));
        }
    }

    public static string HttpsHealth(int port, string cerPath)
    {
        X509Certificate2 expected = X509CertificateLoader.LoadCertificateFromFile(cerPath);
        string want = expected.GetCertHashString();
        HttpClientHandler handler = new HttpClientHandler();
        handler.ServerCertificateCustomValidationCallback = (req, got, chain, errors) =>
            got != null && got.GetCertHashString() == want;
        using (HttpClient client = new HttpClient(handler))
        {
            client.Timeout = TimeSpan.FromSeconds(10);
            return client.GetStringAsync("https://127.0.0.1:" + port + "/health").GetAwaiter().GetResult();
        }
    }

    public static void Tls10MustFail(int port)
    {
        using (TcpClient tcp = new TcpClient())
        {
            tcp.Connect(IPAddress.Loopback, port);
            using (SslStream s = new SslStream(tcp.GetStream(), false, (a, b, c, d) => true))
            {
                try
                {
                    s.AuthenticateAsClient("localhost", null, SslProtocols.Tls, false);
                    throw new InvalidOperationException("tls1.0 handshake must fail");
                }
                catch (AuthenticationException) { }
                catch (IOException) { }
            }
        }
    }

    public static int TlsEcho(string pfxPath, string password)
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
            System.Threading.Thread inner = new System.Threading.Thread(() => Serve(c, cert));
            inner.IsBackground = true;
            inner.Start();
        }
    }

    static void Serve(TcpClient c, X509Certificate2 cert)
    {
        try
        {
            using (c)
            using (SslStream s = new SslStream(c.GetStream(), false))
            {
                s.AuthenticateAsServer(cert, false, SslProtocols.Tls12 | SslProtocols.Tls13, false);
                byte[] buf = new byte[256];
                int got = s.Read(buf, 0, buf.Length);
                if (got < 0) return;
                byte[] pong = Encoding.ASCII.GetBytes("PONG");
                s.Write(pong, 0, pong.Length);
                s.Flush();
            }
        }
        catch (Exception) { }
    }
}
