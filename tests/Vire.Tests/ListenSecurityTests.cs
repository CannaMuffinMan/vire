using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Xunit;

public class ListenSecurityTests
{
    [Fact]
    public void AmbiguousFramingIsRefused()
    {
        int port = HighPort();
        using (ListenHost host = ListenHost.Start(OkRoute(), port))
        {
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nContent-Length: 5\r\n\r\nhello"));
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding : chunked\r\nContent-Length: 5\r\n\r\nhello"));
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding\t: chunked\r\nContent-Length: 5\r\n\r\nhello"));
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\nhello"));
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\n Foo: bar\r\nContent-Length: 5\r\n\r\nhello"));
            Assert.Equal(400, Status(host.Port, "GET / HTTP/1.1\rHost: x\r\n\r\n"));
            Assert.Equal(400, Status(host.Port, "GET / HTTP/1.1\r\nHost: x\ry\r\n\r\n"));
            Assert.Equal(400, HttpWire.ParseComplete(Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\nx"), 64).Status);
            AssertUnsafe("GET / HTTP/1.1\nHost: x\r\n\r\n");
            AssertUnsafe("GET / HTTP/1.1\rHost: x\r\n\r\n");
            AssertUnsafe("GET / HTTP/1.1\r\nHost: x\ry\r\n\r\n");
            AssertUnsafe("GET / HTTP/1.1\r\nHost: x\r\n folded\r\n\r\n");
            byte[] ok = Encoding.ASCII.GetBytes("GET / HTTP/1.1\r\nHost: x\r\nX-Foo: bar\r\nSet-Cookie: stolen\r\n\r\n");
            Assert.False(HttpWire.HeaderBytesUnsafe(ok, HttpWire.HeaderEnd(ok, ok.Length)));
            Assert.Equal(0, HttpWire.ParseComplete(ok, ok.Length).Status);
            byte[] query = Encoding.ASCII.GetBytes("GET /api/search?q=hello%20world HTTP/1.1\r\nHost: x\r\n\r\n");
            HttpWire.Result kept = HttpWire.ParseComplete(query, query.Length);
            Assert.Equal(0, kept.Status);
            Assert.Equal("/api/search?q=hello%20world", kept.Path);
        }
    }

    [Fact]
    public void ContentLengthDoesNotWrapOrIgnoreJunk()
    {
        int port = HighPort();
        using (ListenHost host = ListenHost.Start(OkRoute(), port))
        {
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: +5\r\n\r\nhello"));
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\0\r\n\r\nhello"));
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 00\r\n\r\n"));
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2147483648\r\n\r\n"));
            Assert.Equal(400, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 99999999999999999999\r\n\r\n"));
            Assert.Equal(413, Status(host.Port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1000001\r\n\r\n"));
            byte[] plus = Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nContent-Length: +5\r\n\r\nhello");
            Assert.Equal(400, HttpWire.ParseComplete(plus, plus.Length).Status);
            byte[] huge = Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nContent-Length: 99999999999999999999\r\n\r\n");
            Assert.Equal(400, HttpWire.ParseComplete(huge, huge.Length).Status);
        }
    }

    [Fact]
    public void TokenCoversSiteFilesAndDoesNotStopAtAPrefix()
    {
        int port = HighPort();
        string token = "0123456789abcdef";
        TextWriter previous = Console.Out;
        StringWriter logged = new StringWriter();
        Console.SetOut(logged);
        ListenHooks.OverrideEnv = true;
        ListenHooks.BindMode = null;
        ListenHooks.Token = token;
        try
        {
            using (ListenHost host = ListenHost.Start(OkRoute(), port))
            {
                string site = Path.Combine(host.Folder, "site");
                Directory.CreateDirectory(site);
                File.WriteAllText(Path.Combine(site, "index.html"), "SITE");
                File.WriteAllText(Path.Combine(host.Folder, "secret.txt"), "OUTSIDE");
                string page = ReadAll(host.Port, "GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n");
                Assert.StartsWith("HTTP/1.1 401 ", page);
                Assert.DoesNotContain("SITE", page);
                Assert.DoesNotContain(token, page);
                Assert.DoesNotContain(token, logged.ToString());
                string health = ReadAll(host.Port, "GET /health HTTP/1.1\r\nHost: x\r\n\r\n");
                Assert.StartsWith("HTTP/1.1 200 ", health);
                string prefix = ReadAll(host.Port, "POST /api HTTP/1.1\r\nHost: x\r\nX-FCG-Token: 0123456789abcde\r\nContent-Length: 0\r\n\r\n");
                Assert.StartsWith("HTTP/1.1 401 ", prefix);
                string twice = ReadAll(host.Port, "POST /api HTTP/1.1\r\nHost: x\r\nX-FCG-Token: " + token + "\r\nX-FCG-Token: " + token + "\r\nContent-Length: 0\r\n\r\n");
                Assert.StartsWith("HTTP/1.1 401 ", twice);
                string ok = ReadAll(host.Port, "POST /api HTTP/1.1\r\nHost: x\r\nX-FCG-Token: " + token + "\r\nContent-Length: 0\r\n\r\n");
                Assert.StartsWith("HTTP/1.1 200 ", ok);
                Assert.DoesNotContain(token, ok);
                string leaked = ReadAll(host.Port, "GET /%2e%2e/secret.txt HTTP/1.1\r\nHost: x\r\nX-FCG-Token: " + token + "\r\n\r\n");
                Assert.DoesNotContain("OUTSIDE", leaked);
                Assert.StartsWith("HTTP/1.1 404 ", leaked);
                string slash = ReadAll(host.Port, "GET /%2e%2e%5csecret.txt HTTP/1.1\r\nHost: x\r\nX-FCG-Token: " + token + "\r\n\r\n");
                Assert.DoesNotContain("OUTSIDE", slash);
                string data = ReadAll(host.Port, "GET /../data/secret.txt HTTP/1.1\r\nHost: x\r\nX-FCG-Token: " + token + "\r\n\r\n");
                Assert.DoesNotContain("OUTSIDE", data);
            }
            ListenHooks.BindMode = "public";
            ListenHooks.Token = "short-token";
            Assert.Throws<VireError>(() => VireListen.Run(18241, 1, CancellationToken.None, Path.GetTempPath(), null, null, delegate (int p) { }));
        }
        finally
        {
            Console.SetOut(previous);
            ListenHooks.Reset();
        }
    }

    [Fact]
    public void HeadLengthMatchesTheBodyAndHeadersStayUnsplit()
    {
        int port = HighPort();
        using (ListenHost host = ListenHost.Start(OkRoute(), port))
        {
            string site = Path.Combine(host.Folder, "site");
            Directory.CreateDirectory(site);
            File.WriteAllText(Path.Combine(site, "index.html"), "SITE");
            string head = ReadAll(host.Port, "HEAD /index.html HTTP/1.1\r\nHost: x\r\n\r\n");
            Assert.Contains("Content-Length: 4\r\n", head);
            Assert.EndsWith("\r\n\r\n", head);
            Assert.DoesNotContain("SITE", head);
            string injected = ReadAll(host.Port, "GET /index.html%0d%0aX-Injected:%20yes HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Injected: yes\r\n\r\n");
            Assert.DoesNotContain("X-Injected", HeaderBlock(injected));
            Assert.DoesNotContain("\r\n\r\nHTTP/", injected);
        }
    }

    static string OkRoute()
    {
        return "define route with method, path, body\n  return \"ok\"\nend\ndefine main\n  listen with 0\nend\n";
    }

    static int HighPort()
    {
        int prefer = 18241;
        PortGuard.AssertAllowedPort(prefer);
        try
        {
            TcpListener probe = new TcpListener(IPAddress.Loopback, prefer);
            probe.Start();
            probe.Stop();
            return prefer;
        }
        catch (SocketException)
        {
            return PortGuard.GetFreeLoopbackPort();
        }
    }

    static void AssertUnsafe(string request)
    {
        byte[] raw = Encoding.ASCII.GetBytes(request);
        int end = HttpWire.HeaderEnd(raw, raw.Length);
        Assert.True(end >= 0, "expected a header terminator so the scan runs");
        Assert.True(HttpWire.HeaderBytesUnsafe(raw, end));
        Assert.Equal(400, HttpWire.ParseComplete(raw, raw.Length).Status);
    }

    static int Status(int port, string request)
    {
        string text = ReadAll(port, request);
        int space = text.IndexOf(' ');
        int next = space < 0 ? -1 : text.IndexOf(' ', space + 1);
        int code;
        if (space < 0 || next < 0 || !int.TryParse(text.Substring(space + 1, next - space - 1), out code)) return 0;
        return code;
    }

    static string HeaderBlock(string response)
    {
        int split = response.IndexOf("\r\n\r\n", StringComparison.Ordinal);
        if (split < 0) return response;
        return response.Substring(0, split);
    }

    static string ReadAll(int port, string request)
    {
        PortGuard.AssertAllowedPort(port);
        using (TcpClient tcp = new TcpClient())
        {
            tcp.Connect("127.0.0.1", port);
            tcp.ReceiveTimeout = 5000;
            byte[] sent = Encoding.ASCII.GetBytes(request);
            tcp.GetStream().Write(sent, 0, sent.Length);
            MemoryStream buffer = new MemoryStream();
            byte[] chunk = new byte[2048];
            try
            {
                int n;
                while ((n = tcp.GetStream().Read(chunk, 0, chunk.Length)) > 0) buffer.Write(chunk, 0, n);
            }
            catch (IOException) { }
            return Encoding.ASCII.GetString(buffer.ToArray());
        }
    }
}
