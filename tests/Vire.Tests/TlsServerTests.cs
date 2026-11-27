using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using System.Threading;
using Xunit;

public class TlsServerTests : IDisposable
{
    TlsListenHost host;
    string certPath;
    string keyPath;
    string expectedBody;

    public TlsServerTests()
    {
        string root = DualMode.FindRoot();
        expectedBody = HealthBody(root);
        string work = Path.Combine(root, "data", "tls-server-tests");
        Directory.CreateDirectory(work);
        certPath = Path.Combine(work, "tls-health-cert.pem");
        keyPath = Path.Combine(work, "tls-health-key.pem");
        MakeSelfSigned(certPath, keyPath);
        host = TlsListenHost.Start(HealthSource(), certPath, keyPath);
        Assert.True(IPAddress.IsLoopback(IPAddress.Parse("127.0.0.1")));
        PortGuard.AssertAllowedPort(host.Port);
    }

    public void Dispose()
    {
        if (host != null) host.Dispose();
    }

    [Fact]
    public void HealthOverHttpsMatchesContract()
    {
        string root = DualMode.FindRoot();
        using (JsonDocument doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "health.json"))))
        {
            JsonElement contract = doc.RootElement;
            Assert.Equal("GET", contract.GetProperty("method").GetString());
            Assert.Equal("/health", contract.GetProperty("path").GetString());
            Assert.Equal(200, contract.GetProperty("status").GetInt32());
            using (HttpClient client = Https())
            {
                HttpResponseMessage res = client.GetAsync("https://127.0.0.1:" + host.Port + "/health").Result;
                Assert.Equal(contract.GetProperty("status").GetInt32(), (int)res.StatusCode);
                string got = res.Content.ReadAsStringAsync().Result.Trim();
                using (JsonDocument gotDoc = JsonDocument.Parse(got))
                {
                    Assert.True(gotDoc.RootElement.GetProperty("ok").GetBoolean());
                    Assert.Equal("fcgcpa", gotDoc.RootElement.GetProperty("service").GetString());
                    Assert.False(gotDoc.RootElement.GetProperty("payments").GetBoolean());
                }
                using (JsonDocument wantDoc = JsonDocument.Parse(expectedBody))
                {
                    Assert.Equal(wantDoc.RootElement.GetProperty("service").GetString(), JsonDocument.Parse(got).RootElement.GetProperty("service").GetString());
                }
            }
        }
    }

    [Fact]
    public void DualModeTlsListenRefusesPathTraversal()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define route with method, path, body\n  return \"{\\\"ok\\\":true}\"\nend\n" +
            "define main\n  tls_listen with 18443, \"../etc/passwd\", \"data/k.pem\"\nend\n",
            null);
        Assert.True(run.Matched, Diff(run));
        Assert.Equal(1, run.InterpCode);
        Assert.Contains("folder", DualMode.Norm(run.InterpErr) + DualMode.Norm(run.InterpOut));
    }

    [Fact]
    public void DualModeTlsListenRefusesMissingCert()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define route with method, path, body\n  return \"{\\\"ok\\\":true}\"\nend\n" +
            "define main\n  tls_listen with 18443, \"data/no-such-cert.pem\", \"data/no-such-key.pem\"\nend\n",
            null);
        Assert.True(run.Matched, Diff(run));
        Assert.Equal(1, run.InterpCode);
        string err = DualMode.Norm(run.InterpErr) + DualMode.Norm(run.InterpOut);
        Assert.Contains("tls certificate", err);
    }

    [Fact]
    public void PlaintextOnTlsPortFailsClosed()
    {
        using (TcpClient client = new TcpClient())
        {
            client.Connect("127.0.0.1", host.Port);
            NetworkStream stream = client.GetStream();
            byte[] req = Encoding.ASCII.GetBytes("GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n");
            stream.Write(req, 0, req.Length);
            stream.ReadTimeout = 3000;
            byte[] buf = new byte[256];
            int n;
            try { n = stream.Read(buf, 0, buf.Length); }
            catch (IOException) { n = 0; }
            string text = n > 0 ? Encoding.ASCII.GetString(buf, 0, n) : "";
            Assert.DoesNotContain("HTTP/", text);
            Assert.DoesNotContain("fcgcpa", text);
        }
    }

    [Fact]
    public void TruncatedHandshakeFailsClosed()
    {
        using (TcpClient client = new TcpClient())
        {
            client.Connect("127.0.0.1", host.Port);
            NetworkStream stream = client.GetStream();
            byte[] cut = new byte[] { 0x16, 0x03, 0x03, 0x00, 0x10, 0x01, 0x00 };
            stream.Write(cut, 0, cut.Length);
            stream.ReadTimeout = 3000;
            byte[] buf = new byte[256];
            int n;
            try { n = stream.Read(buf, 0, buf.Length); }
            catch (IOException) { n = 0; }
            string text = n > 0 ? Encoding.ASCII.GetString(buf, 0, n) : "";
            Assert.DoesNotContain("HTTP/", text);
            Assert.DoesNotContain("{\"ok\"", text);
        }
    }

    [Fact]
    public void Tls10ClientFailsClosed()
    {
        using (TcpClient client = new TcpClient())
        {
            client.Connect("127.0.0.1", host.Port);
            using (SslStream ssl = new SslStream(client.GetStream(), false, delegate { return true; }))
            {
                bool failed = false;
                try
                {
#pragma warning disable SYSLIB0039, CS0618
                    ssl.AuthenticateAsClient(new SslClientAuthenticationOptions
                    {
                        TargetHost = "localhost",
                        EnabledSslProtocols = SslProtocols.Tls | SslProtocols.Tls11,
                        EncryptionPolicy = EncryptionPolicy.RequireEncryption
                    });
#pragma warning restore SYSLIB0039, CS0618
                }
                catch (AuthenticationException) { failed = true; }
                catch (IOException) { failed = true; }
                catch (PlatformNotSupportedException) { failed = true; }
                catch (VireError) { failed = true; }
                Assert.True(failed, "TLS 1.0/1.1 must not complete a handshake");
            }
        }
    }

    [Fact]
    public void NativeSourcesWireTlsListenServer()
    {
        string root = DualMode.FindRoot();
        string tls = File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire"));
        Assert.Contains("iat_usecert", tls);
        Assert.Contains("iat_sslacc", tls);
        Assert.Contains("rt_listen", tls);
        Assert.DoesNotContain("native tls_listen is fail-closed", tls);
        Assert.Contains("\"/health\"", File.ReadAllText(Path.Combine(root, "guest-health-tls.vire")));
        Assert.Contains("fcgcpa", File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "health.json")));
        string win = File.ReadAllText(Path.Combine(root, "tools", "tls-server-windows.ps1"));
        Assert.Contains("guest-health-tls.vire", win);
        Assert.DoesNotContain("data/guest-health-tls.vire", win);
    }

    HttpClient Https()
    {
        X509Certificate2 expected = X509CertificateLoader.LoadCertificateFromFile(certPath);
        string want = expected.GetCertHashString();
        HttpClientHandler handler = new HttpClientHandler();
        handler.ServerCertificateCustomValidationCallback = delegate (HttpRequestMessage req, X509Certificate2 got, X509Chain chain, SslPolicyErrors errors)
        {
            return got != null && got.GetCertHashString() == want;
        };
        HttpClient client = new HttpClient(handler);
        client.Timeout = TimeSpan.FromSeconds(15);
        return client;
    }

    static string HealthBody(string root)
    {
        using (JsonDocument doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "health.json"))))
        {
            return JsonSerializer.Serialize(doc.RootElement.GetProperty("body"));
        }
    }

    static string HealthSource()
    {
        return string.Join("\n", new string[]
        {
            "define route with method, path, body",
            "  if method == \"GET\"",
            "    if path == \"/health\"",
            "      return \"{\\\"ok\\\":true,\\\"service\\\":\\\"fcgcpa\\\",\\\"payments\\\":false}\"",
            "    end",
            "  end",
            "  return \"{\\\"ok\\\":false,\\\"status\\\":404,\\\"error\\\":\\\"not found\\\"}\"",
            "end",
            "define main",
            "  tls_listen with 0, \"data/tls-health-cert.pem\", \"data/tls-health-key.pem\"",
            "end",
            ""
        });
    }

    static void MakeSelfSigned(string certPath, string keyPath)
    {
        using (RSA rsa = RSA.Create(2048))
        {
            CertificateRequest req = new CertificateRequest("CN=localhost", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            SubjectAlternativeNameBuilder san = new SubjectAlternativeNameBuilder();
            san.AddDnsName("localhost");
            san.AddIpAddress(IPAddress.Loopback);
            req.CertificateExtensions.Add(san.Build());
            using (X509Certificate2 cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddHours(-1), DateTimeOffset.UtcNow.AddDays(1)))
            {
                File.WriteAllText(certPath, cert.ExportCertificatePem());
                File.WriteAllText(keyPath, rsa.ExportRSAPrivateKeyPem());
            }
        }
    }

    static string Diff(DualMode.DualRun run)
    {
        return "interp=" + run.InterpCode + " compiled=" + run.CompCode
            + " err=" + DualMode.Norm(run.InterpErr) + "/" + DualMode.Norm(run.CompErr);
    }
}

sealed class TlsListenHost : IDisposable
{
    public int Port;
    CancellationTokenSource cts;
    Thread thread;
    string folder;

    public static TlsListenHost Start(string source, string certPath, string keyPath)
    {
        TlsListenHost host = new TlsListenHost();
        host.folder = Path.Combine(Path.GetTempPath(), "vire-tls-listen-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(host.folder);
        Directory.CreateDirectory(Path.Combine(host.folder, "data"));
        File.Copy(certPath, Path.Combine(host.folder, "data", "tls-health-cert.pem"), true);
        File.Copy(keyPath, Path.Combine(host.folder, "data", "tls-health-key.pem"), true);
        string program = Path.Combine(host.folder, "listen.vire");
        File.WriteAllText(program, source);
        Dictionary<string, Func> funcs = Program.Load(program, host.folder, new HashSet<string>());
        Machine machine = new Machine(funcs, host.folder);
        machine.UseBudget(5000000);
        host.cts = new CancellationTokenSource();
        string absCert = Path.Combine(host.folder, "data", "tls-health-cert.pem");
        string absKey = Path.Combine(host.folder, "data", "tls-health-key.pem");
        host.thread = new Thread(() => machine.ListenCoreTls(0, 1, host.cts.Token, absCert, absKey));
        host.thread.IsBackground = true;
        host.thread.Start();
        DateTime until = DateTime.UtcNow.AddSeconds(5);
        while (machine.ListenPort == 0 && DateTime.UtcNow < until)
            Thread.Sleep(10);
        host.Port = machine.ListenPort;
        PortGuard.AssertAllowedPort(host.Port);
        Assert.InRange(host.Port, 1024, 65535);
        return host;
    }

    public void Dispose()
    {
        if (cts != null) cts.Cancel();
        if (thread != null) thread.Join(8000);
        try
        {
            if (folder != null && Directory.Exists(folder))
                Directory.Delete(folder, true);
        }
        catch (IOException) { }
    }
}
