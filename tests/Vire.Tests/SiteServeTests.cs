using System;
using System.IO;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using Xunit;

public class SiteServeTests
{
    [Fact]
    public void HostServesEtag304AndRefusesTraversal()
    {
        using (ListenHost host = ListenHost.Start(Source()))
        {
            string site = Path.Combine(host.Folder, "site");
            Directory.CreateDirectory(site);
            File.WriteAllText(Path.Combine(site, "index.html"), "<html>{{year}}</html>");
            File.WriteAllText(Path.Combine(site, "note.txt"), "hello-site");
            using (HttpClient client = new HttpClient())
            {
                client.Timeout = TimeSpan.FromSeconds(10);
                string baseUrl = "http://127.0.0.1:" + host.Port;
                HttpResponseMessage page = client.GetAsync(baseUrl + "/").Result;
                Assert.Equal(200, (int)page.StatusCode);
                string html = page.Content.ReadAsStringAsync().Result;
                Assert.Equal("<html>2026</html>", html);
                Assert.True(page.Headers.Contains("ETag") || page.Content.Headers.Contains("ETag"));
                string etag = page.Headers.Contains("ETag")
                    ? string.Join("", page.Headers.GetValues("ETag"))
                    : string.Join("", page.Content.Headers.GetValues("ETag"));
                HttpRequestMessage nm = new HttpRequestMessage(HttpMethod.Get, baseUrl + "/");
                nm.Headers.TryAddWithoutValidation("If-None-Match", etag);
                HttpResponseMessage notMod = client.SendAsync(nm).Result;
                Assert.Equal(304, (int)notMod.StatusCode);

                HttpResponseMessage txt = client.GetAsync(baseUrl + "/note.txt").Result;
                Assert.Equal("hello-site", txt.Content.ReadAsStringAsync().Result);

                HttpResponseMessage trav = Raw(host.Port, "GET /../Vire.cs HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
                Assert.Equal(404, (int)trav.StatusCode);
                HttpResponseMessage enc = Raw(host.Port, "GET /%2e%2e/Vire.cs HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
                Assert.Equal(404, (int)enc.StatusCode);
                HttpResponseMessage bs = Raw(host.Port, "GET /..\\note.txt HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
                Assert.Equal(404, (int)bs.StatusCode);
                HttpResponseMessage post = Raw(host.Port, "POST /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n");
                Assert.Equal(405, (int)post.StatusCode);
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
            byte[] body = split >= 0 && split + 4 <= raw.Length
                ? Slice(raw, split + 4)
                : new byte[0];
            string[] first = head.Split(new char[] { ' ' }, 3);
            int code = 0;
            if (first.Length >= 2) int.TryParse(first[1], out code);
            HttpResponseMessage message = new HttpResponseMessage((System.Net.HttpStatusCode)code);
            message.Content = new ByteArrayContent(body);
            return message;
        }
    }

    static byte[] Slice(byte[] raw, int start)
    {
        byte[] outBytes = new byte[raw.Length - start];
        Buffer.BlockCopy(raw, start, outBytes, 0, outBytes.Length);
        return outBytes;
    }

    static string Source()
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
}
