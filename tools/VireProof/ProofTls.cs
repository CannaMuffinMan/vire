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

    static X509Certificate2 MakeCert(RSA rsa, HashAlgorithmName hash, bool expired)
    {
        CertificateRequest req = new CertificateRequest("CN=localhost", rsa, hash, RSASignaturePadding.Pkcs1);
        SubjectAlternativeNameBuilder san = new SubjectAlternativeNameBuilder();
        san.AddDnsName("localhost");
        san.AddIpAddress(IPAddress.Loopback);
        req.CertificateExtensions.Add(san.Build());
        DateTimeOffset notBefore = expired ? DateTimeOffset.UtcNow.AddDays(-14) : DateTimeOffset.UtcNow.AddHours(-1);
        DateTimeOffset notAfter = expired ? DateTimeOffset.UtcNow.AddDays(-7) : DateTimeOffset.UtcNow.AddDays(7);
        return req.CreateSelfSigned(notBefore, notAfter);
    }

    public static void WritePem(string certPath, string keyPath)
    {
        using (RSA rsa = RSA.Create(2048))
        using (X509Certificate2 cert = MakeCert(rsa, HashAlgorithmName.SHA256, false))
        {
            Encoding utf8 = new UTF8Encoding(false);
            File.WriteAllText(certPath, cert.ExportCertificatePem(), utf8);
            File.WriteAllText(keyPath, rsa.ExportRSAPrivateKeyPem(), utf8);
        }
    }

    static HashAlgorithmName ParseHash(string name)
    {
        if (name == "sha384") return HashAlgorithmName.SHA384;
        if (name == "sha512") return HashAlgorithmName.SHA512;
        return HashAlgorithmName.SHA256;
    }

    public static void WritePfx(string pfxPath, string cerPath, string password, bool expired, string hashName)
    {
        using (RSA rsa = RSA.Create(2048))
        using (X509Certificate2 cert = MakeCert(rsa, ParseHash(hashName), expired))
        {
            string pw = password ?? "";
            X509Certificate2 exportCert = cert.HasPrivateKey ? cert : cert.CopyWithPrivateKey(rsa);
            File.WriteAllBytes(pfxPath, exportCert.Export(X509ContentType.Pfx, pw));
            File.WriteAllText(cerPath, Pem("CERTIFICATE", exportCert.Export(X509ContentType.Cert)), new UTF8Encoding(false));
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

    public static SslServerAuthenticationOptions ServerOpts(X509Certificate2 cert)
    {
        SslServerAuthenticationOptions opts = new SslServerAuthenticationOptions
        {
            ServerCertificate = cert,
            EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13,
            CertificateRevocationCheckMode = X509RevocationMode.NoCheck,
            ClientCertificateRequired = false,
            EncryptionPolicy = EncryptionPolicy.RequireEncryption
        };
        if (!OperatingSystem.IsWindows())
        {
            try
            {
                opts.CipherSuitesPolicy = new CipherSuitesPolicy(new TlsCipherSuite[]
                {
                    TlsCipherSuite.TLS_AES_128_GCM_SHA256,
                    TlsCipherSuite.TLS_AES_256_GCM_SHA384,
                    TlsCipherSuite.TLS_CHACHA20_POLY1305_SHA256,
                    TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
                    TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
                    TlsCipherSuite.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256
                });
            }
            catch (PlatformNotSupportedException) { }
        }
        return opts;
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
                s.AuthenticateAsServer(ServerOpts(cert));
                byte[] buf = new byte[256];
                int got = s.Read(buf, 0, buf.Length);
                if (got < 0) return;
                byte[] pong = Encoding.ASCII.GetBytes("PONG");
                s.Write(pong, 0, pong.Length);
                s.Flush();
                try { c.Client.Shutdown(SocketShutdown.Send); } catch (Exception) { }
            }
        }
        catch (Exception) { }
    }
}
