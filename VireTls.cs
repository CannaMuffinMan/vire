using System;
using System.IO;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
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
            X509Certificate2 pem = X509Certificate2.CreateFromPemFile(certPath, keyPath);
            return X509CertificateLoader.LoadPkcs12(pem.Export(X509ContentType.Pfx), (string)null);
        }
        catch (VireError) { throw; }
        catch (Exception)
        {
            throw new VireError("could not load that tls certificate", line, column);
        }
    }

    internal static SslStream WrapServer(Stream inner, X509Certificate2 cert, int line)
    {
        SslStream ssl = new SslStream(inner, false);
        try
        {
            ssl.AuthenticateAsServer(new SslServerAuthenticationOptions
            {
                ServerCertificate = cert,
                EnabledSslProtocols = Tls12Plus,
                CertificateRevocationCheckMode = X509RevocationMode.NoCheck,
                ClientCertificateRequired = false,
                EncryptionPolicy = EncryptionPolicy.RequireEncryption
            });
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
        Socket socket = table.Need(sock, line, column);
        try
        {
            NetworkStream inner = new NetworkStream(socket, false);
            SslStream ssl = new SslStream(inner, false, null, null);
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
            ssl.AuthenticateAsClient(opts);
            table.AttachTls(sock, ssl);
            return sock;
        }
        catch (VireError)
        {
            table.Close(sock, line, column);
            throw;
        }
        catch (Exception)
        {
            try { table.Close(sock, line, column); } catch (Exception) { }
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
