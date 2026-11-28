using System;
using System.IO;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

static class VireTls
{
    const int ConnectTimeoutMs = 5000;
    const SslProtocols Tls12Plus = SslProtocols.Tls12 | SslProtocols.Tls13;

    internal static X509Certificate2 LoadPemPair(string certPath, string keyPath, int line, int column)
    {
        if (string.IsNullOrEmpty(certPath) || string.IsNullOrEmpty(keyPath))
            throw new VireError("tls_listen needs a certificate file and a key file", line, column);
        try
        {
            string certPem = File.ReadAllText(certPath);
            string keyPem = File.ReadAllText(keyPath);
            using (X509Certificate2 loaded = X509Certificate2.CreateFromPem(certPem, keyPem))
            {
                byte[] pfx = loaded.Export(X509ContentType.Pfx);
                X509KeyStorageFlags flags = X509KeyStorageFlags.Exportable;
                if (OperatingSystem.IsWindows())
                    flags |= X509KeyStorageFlags.UserKeySet | X509KeyStorageFlags.PersistKeySet;
                else
                    flags |= X509KeyStorageFlags.EphemeralKeySet;
                return X509CertificateLoader.LoadPkcs12(pfx, (string)null, flags);
            }
        }
        catch (VireError) { throw; }
        catch (Exception)
        {
            throw new VireError("could not load that tls certificate", line, column);
        }
    }

    internal static SslStream WrapServer(Stream inner, X509Certificate2 cert, int line)
    {
        if (inner.CanTimeout)
        {
            inner.ReadTimeout = ConnectTimeoutMs;
            inner.WriteTimeout = ConnectTimeoutMs;
        }
        SslStream ssl = new SslStream(inner, false);
        try
        {
            SslServerAuthenticationOptions opts = new SslServerAuthenticationOptions
            {
                ServerCertificate = cert,
                EnabledSslProtocols = Tls12Plus,
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
                        TlsCipherSuite.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
                        TlsCipherSuite.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
                        TlsCipherSuite.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,
                        TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
                        TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
                        TlsCipherSuite.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256
                    });
                }
                catch (PlatformNotSupportedException) { }
            }
            ssl.AuthenticateAsServer(opts);
            return ssl;
        }
        catch (Exception)
        {
            try { ssl.Dispose(); } catch (Exception) { }
            throw new VireError("tls handshake failed", line);
        }
    }

    internal static int Connect(string host, object portObj, string name, string caPath, VireTcpTable table, string root, int line, int column)
    {
        if (host == null || name == null)
            throw new VireError("tls_connect needs a host, a port, a name, and a ca file", line, column);
        if (caPath == null)
            throw new VireError("tls_connect needs a host, a port, a name, and a ca file", line, column);
        if (name.Length < 1)
            throw new VireError("tls_connect needs a server name", line, column);
        int sock = VireNet.ConnectHost(host, portObj, table, line, column);
        try
        {
            Handshake(sock, name, caPath, 1, table, line, column);
            return sock;
        }
        catch
        {
            try { table.Close(sock, line, column); } catch (Exception) { }
            throw;
        }
    }

    internal static int Wrap(object handle, string name, string caPath, object checkHostObj, VireTcpTable table, int line, int column)
    {
        if (!(handle is int))
            throw new VireError("tls_wrap needs a connection, a name, a ca file, and a host check", line, column);
        if (name == null || caPath == null)
            throw new VireError("tls_wrap needs a connection, a name, a ca file, and a host check", line, column);
        if (name.Length < 1)
            throw new VireError("tls_connect needs a server name", line, column);
        int checkHost = 1;
        if (checkHostObj is int)
            checkHost = (int)checkHostObj;
        if (checkHost != 0 && checkHost != 1)
            throw new VireError("tls_wrap needs a connection, a name, a ca file, and a host check", line, column);
        int sock = (int)handle;
        table.Need(sock, line, column);
        Handshake(sock, name, caPath, checkHost, table, line, column);
        return sock;
    }

    static void Handshake(int sock, string name, string caPath, int checkHost, VireTcpTable table, int line, int column)
    {
        Socket socket = table.Need(sock, line, column);
        NetworkStream inner = new NetworkStream(socket, false);
        SslStream ssl = new SslStream(inner, false, null, null);
        try
        {
            SslClientAuthenticationOptions opts = new SslClientAuthenticationOptions
            {
                TargetHost = name,
                EnabledSslProtocols = Tls12Plus,
                EncryptionPolicy = EncryptionPolicy.RequireEncryption
            };
            if (caPath.Length == 0)
            {
                opts.CertificateRevocationCheckMode = X509RevocationMode.Online;
            }
            else
            {
                string caFile;
                try { caFile = File.ReadAllText(caPath); }
                catch (Exception) { throw new VireError("could not read that ca file", line, column); }
                X509Certificate2 ca = X509CertificateLoader.LoadCertificate(PemToDer(caFile, line, column));
                X509ChainPolicy policy = new X509ChainPolicy();
                policy.TrustMode = X509ChainTrustMode.CustomRootTrust;
                policy.CustomTrustStore.Add(ca);
                policy.RevocationMode = X509RevocationMode.NoCheck;
                opts.CertificateChainPolicy = policy;
                opts.CertificateRevocationCheckMode = X509RevocationMode.NoCheck;
            }
            if (checkHost == 0)
            {
                opts.RemoteCertificateValidationCallback = (sender, cert, chain, errors) =>
                {
                    return (errors & ~SslPolicyErrors.RemoteCertificateNameMismatch) == SslPolicyErrors.None;
                };
            }
            ssl.AuthenticateAsClient(opts);
            table.AttachTls(sock, ssl);
        }
        catch (VireError)
        {
            try { ssl.Dispose(); } catch (Exception) { }
            throw;
        }
        catch (Exception)
        {
            try { ssl.Dispose(); } catch (Exception) { }
            throw new VireError("tls handshake failed", line, column);
        }
    }

    static byte[] PemToDer(string pem, int line, int column)
    {
        const string begin = "-----BEGIN CERTIFICATE-----";
        const string end = "-----END CERTIFICATE-----";
        int a = pem.IndexOf(begin, StringComparison.Ordinal);
        int b = pem.IndexOf(end, StringComparison.Ordinal);
        if (a < 0 || b < 0 || b <= a)
            throw new VireError("that ca file is not a certificate", line, column);
        string b64 = pem.Substring(a + begin.Length, b - (a + begin.Length)).Replace("\r", "").Replace("\n", "").Replace(" ", "");
        try { return Convert.FromBase64String(b64); }
        catch (FormatException) { throw new VireError("that ca file is not a certificate", line, column); }
    }

    internal static int SendAll(object handle, object payload, VireTcpTable table, int line, int column)
    {
        SslStream tls = table.NeedTls(handle, line, column);
        string text = payload as string;
        if (text == null) throw new VireError("tls_send needs a connection and text", line, column);
        byte[] raw = new byte[text.Length];
        for (int i = 0; i < text.Length; i++)
        {
            int c = text[i];
            if (c > 255) throw new VireError("tls_send needs a connection and text", line, column);
            raw[i] = (byte)c;
        }
        try
        {
            tls.Write(raw, 0, raw.Length);
            tls.Flush();
            return raw.Length;
        }
        catch (Exception) { throw new VireError("tls handshake failed", line, column); }
    }

    internal static string RecvBound(object handle, object maxObj, VireTcpTable table, int line, int column)
    {
        SslStream tls = table.NeedTls(handle, line, column);
        if (!(maxObj is int)) throw new VireError("tls_recv needs a connection and a size", line, column);
        int max = (int)maxObj;
        if (max < 0) throw new VireError("tls_recv needs a connection and a size", line, column);
        if (max > 1000000) max = 1000000;
        if (max == 0) return "";
        byte[] buf = new byte[max];
        try
        {
            tls.ReadTimeout = ConnectTimeoutMs;
            int n = tls.Read(buf, 0, max);
            if (n <= 0) return "";
            char[] chars = new char[n];
            for (int i = 0; i < n; i++) chars[i] = (char)buf[i];
            return new string(chars);
        }
        catch (Exception) { throw new VireError("tls handshake failed", line, column); }
    }

    internal static object CloseHandle(object handle, VireTcpTable table, int line, int column)
    {
        table.CloseTls(handle, line, column);
        return null;
    }
}
