using System;
using System.IO;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using Xunit;

public class ServeTests
{
    [Fact]
    public void ServeBuiltinIsRemoved()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-c8-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string program = Path.Combine(dir, "old-serve.vire");
            File.WriteAllText(program, "define main\n  serve with 8080\nend\n");
            TextWriter previousOut = Console.Out;
            TextWriter previousErr = Console.Error;
            StringWriter err = new StringWriter();
            Console.SetOut(new StringWriter());
            Console.SetError(err);
            int code;
            try { code = Program.Execute(new string[] { program }); }
            finally
            {
                Console.SetOut(previousOut);
                Console.SetError(previousErr);
            }
            Assert.Equal(1, code);
            Assert.Contains("serve was removed; use listen", err.ToString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void VaultSampleStillBuilds()
    {
        string root = FindRoot();
        string dir = Path.Combine(Path.GetTempPath(), "vire-vault-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        Directory.CreateDirectory(Path.Combine(dir, "site", "videos"));
        try
        {
            File.Copy(Path.Combine(root, "vault.vire"), Path.Combine(dir, "vault.vire"));
            TextWriter previousOut = Console.Out;
            TextWriter previousErr = Console.Error;
            StringWriter output = new StringWriter();
            Console.SetOut(output);
            Console.SetError(new StringWriter());
            int code;
            try { code = Program.Execute(new string[] { Path.Combine(dir, "vault.vire") }); }
            finally
            {
                Console.SetOut(previousOut);
                Console.SetError(previousErr);
            }
            Assert.Equal(0, code);
            Assert.Contains("vault written", output.ToString());
            Assert.True(File.Exists(Path.Combine(dir, "site", "index.html")));
            Assert.True(File.Exists(Path.Combine(dir, "site", "vault.js")));
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void ListenServesSiteAndRefusesTraversalSymlinkAndVire()
    {
        using (ListenHost host = ListenHost.Start(SiteListenSource()))
        {
            string site = Path.Combine(host.Folder, "site");
            Directory.CreateDirectory(Path.Combine(site, "videos"));
            File.WriteAllText(Path.Combine(site, "index.html"), "<html>ok</html>");
            File.WriteAllText(Path.Combine(site, "secret.vire"), "define main\nend\n");
            byte[] video = Encoding.ASCII.GetBytes("0123456789abcdef");
            File.WriteAllBytes(Path.Combine(site, "videos", "clip.mp4"), video);

            using (HttpClient client = new HttpClient())
            {
                client.Timeout = TimeSpan.FromSeconds(10);
                string baseUrl = "http://127.0.0.1:" + host.Port;
                HttpResponseMessage page = client.GetAsync(baseUrl + "/").Result;
                Assert.Equal(200, (int)page.StatusCode);
                Assert.Equal("<html>ok</html>", page.Content.ReadAsStringAsync().Result);
                Assert.Contains("nosniff", string.Join(" ", page.Headers.GetValues("X-Content-Type-Options")));
                Assert.Contains("default-src 'self'", string.Join(" ", page.Headers.GetValues("Content-Security-Policy")));

                HttpResponseMessage vire = client.GetAsync(baseUrl + "/secret.vire").Result;
                Assert.Equal(404, (int)vire.StatusCode);

                HttpResponseMessage traversal = Raw(host.Port, "GET /../Vire.cs HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
                Assert.Equal(404, (int)traversal.StatusCode);

                HttpResponseMessage encoded = Raw(host.Port, "GET /%2e%2e/Vire.cs HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
                Assert.Equal(404, (int)encoded.StatusCode);

                string outside = Path.Combine(Path.GetTempPath(), "vire-c8-out-" + Guid.NewGuid().ToString("N") + ".html");
                File.WriteAllText(outside, "leaked");
                string link = Path.Combine(site, "link.html");
                bool linked = false;
                try
                {
                    File.CreateSymbolicLink(link, outside);
                    linked = File.Exists(link) || Directory.Exists(link);
                }
                catch (Exception ex)
                {
                    Console.WriteLine("symlink test skipped: " + ex.GetType().Name);
                }
                if (linked)
                {
                    HttpResponseMessage viaLink = client.GetAsync(baseUrl + "/link.html").Result;
                    Assert.Equal(404, (int)viaLink.StatusCode);
                }
                try { File.Delete(outside); } catch (IOException) { }

                HttpResponseMessage ranged = Raw(host.Port,
                    "GET /videos/clip.mp4 HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-3\r\n\r\n");
                Assert.Equal(206, (int)ranged.StatusCode);
                Assert.Equal("0123", ranged.Content.ReadAsStringAsync().Result);

                HttpResponseMessage badRange = Raw(host.Port,
                    "GET /videos/clip.mp4 HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=99-100\r\n\r\n");
                Assert.Equal(416, (int)badRange.StatusCode);
            }
        }
    }

    static HttpResponseMessage Raw(int port, string request)
    {
        PortGuard.AssertAllowedPort(port);
        using (TcpClient tcp = new TcpClient())
        {
            tcp.Connect("127.0.0.1", port);
            NetworkStream stream = tcp.GetStream();
            byte[] sent = Encoding.ASCII.GetBytes(request);
            stream.Write(sent, 0, sent.Length);
            tcp.ReceiveTimeout = 5000;
            MemoryStream buffer = new MemoryStream();
            byte[] chunk = new byte[4096];
            try
            {
                int n;
                while ((n = stream.Read(chunk, 0, chunk.Length)) > 0) buffer.Write(chunk, 0, n);
            }
            catch (IOException) { }
            byte[] raw = buffer.ToArray();
            string text = Encoding.ASCII.GetString(raw);
            int split = text.IndexOf("\r\n\r\n", StringComparison.Ordinal);
            string head = split >= 0 ? text.Substring(0, split) : text;
            byte[] body = split >= 0 ? Encoding.UTF8.GetBytes(text.Substring(split + 4)) : new byte[0];
            string[] first = head.Split(new char[] { ' ' }, 3);
            int code = 0;
            if (first.Length >= 2) int.TryParse(first[1], out code);
            HttpResponseMessage message = new HttpResponseMessage((System.Net.HttpStatusCode)code);
            message.Content = new ByteArrayContent(body);
            return message;
        }
    }

    static string SiteListenSource()
    {
        return string.Join("\n", new string[]
        {
            "define route with method, path, body",
            "  return \"{\\\"ok\\\":false,\\\"status\\\":404,\\\"error\\\":\\\"not found\\\"}\"",
            "end",
            "define main",
            "  listen with 0",
            "end",
            ""
        });
    }

    static string FindRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "vire.csproj"))) return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root");
    }
}
