using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using Xunit;

[Collection("listen")]
public class BlockAuthTests
{
    const string WriteToken = "test-block-token1";

    [Fact]
    public void PostBlockWithoutSecretIs401AndDoesNotAppend()
    {
        ListenHooks.Reset();
        using (ListenHost host = ListenHost.Start(ChainSource()))
        {
            string before = GetChain(host.Port);
            string none = ReadAll(host.Port, PostBlock("{\"text\":\"no-token\"}", null));
            Assert.StartsWith("HTTP/1.1 401 ", none);
            Assert.DoesNotContain("accepted", none);
            Assert.Equal(before, GetChain(host.Port));
        }
    }

    [Fact]
    public void PostBlockBearerCasesRefuseOrAppend()
    {
        ListenHooks.Reset();
        ListenHooks.OverrideEnv = true;
        ListenHooks.BlockToken = WriteToken;
        try
        {
            using (ListenHost host = ListenHost.Start(ChainSource()))
            {
                string before = GetChain(host.Port);
                string none = ReadAll(host.Port, PostBlock("{\"text\":\"none\"}", null));
                Assert.StartsWith("HTTP/1.1 401 ", none);
                Assert.DoesNotContain(WriteToken, none);

                string wrong = ReadAll(host.Port, PostBlock("{\"text\":\"wrong\"}", "Bearer wrong-token-16x"));
                Assert.StartsWith("HTTP/1.1 401 ", wrong);
                Assert.DoesNotContain(WriteToken, wrong);

                string shortTok = ReadAll(host.Port, PostBlock("{\"text\":\"short\"}", "Bearer short-token"));
                Assert.StartsWith("HTTP/1.1 401 ", shortTok);

                string xjson = "{\"text\":\"xfcg\"}";
                string xfcg = ReadAll(host.Port, "POST /block HTTP/1.1\r\nHost: x\r\nX-FCG-Token: " + WriteToken
                    + "\r\nContent-Length: " + Encoding.UTF8.GetByteCount(xjson) + "\r\n\r\n" + xjson);
                Assert.StartsWith("HTTP/1.1 401 ", xfcg);

                Assert.Equal(before, GetChain(host.Port));

                string ok = ReadAll(host.Port, PostBlock("{\"text\":\"hello\"}", "Bearer " + WriteToken));
                Assert.StartsWith("HTTP/1.1 200 ", ok);
                Assert.Contains("\"accepted\":true", ok);
                Assert.DoesNotContain(WriteToken, ok);
                string after = GetChain(host.Port);
                Assert.NotEqual(before, after);
                Assert.Contains("hello", after);

                string health = ReadAll(host.Port, "GET /health HTTP/1.1\r\nHost: x\r\n\r\n");
                Assert.StartsWith("HTTP/1.1 200 ", health);
                string info = ReadAll(host.Port, "GET /info HTTP/1.1\r\nHost: x\r\n\r\n");
                Assert.StartsWith("HTTP/1.1 200 ", info);
            }
        }
        finally
        {
            ListenHooks.Reset();
        }
    }

    [Fact]
    public void ShortConfiguredBlockTokenStillDeniesWrites()
    {
        ListenHooks.Reset();
        ListenHooks.OverrideEnv = true;
        ListenHooks.BlockToken = "short-token";
        try
        {
            using (ListenHost host = ListenHost.Start(ChainSource()))
            {
                string before = GetChain(host.Port);
                string res = ReadAll(host.Port, PostBlock("{\"text\":\"x\"}", "Bearer short-token"));
                Assert.StartsWith("HTTP/1.1 401 ", res);
                Assert.Equal(before, GetChain(host.Port));
            }
        }
        finally
        {
            ListenHooks.Reset();
        }
    }

    [Fact]
    public void BearerMatchDoesNotStopAtAPrefixAndIgnoresDuplicates()
    {
        Assert.False(Program.HeaderBearerMatches("POST /block HTTP/1.1\r\nAuthorization: Bearer test-block-token\r\n\r\n", WriteToken));
        Assert.False(Program.HeaderBearerMatches(
            "POST /block HTTP/1.1\r\nAuthorization: Bearer " + WriteToken + "\r\nAuthorization: Bearer " + WriteToken + "\r\n\r\n",
            WriteToken));
        Assert.True(Program.HeaderBearerMatches("POST /block HTTP/1.1\r\nAuthorization: Bearer " + WriteToken + "\r\n\r\n", WriteToken));
        Assert.True(Program.HeaderBearerMatches("POST /block HTTP/1.1\r\nAuthorization: bearer " + WriteToken + "\r\n\r\n", WriteToken));
        Assert.False(Program.HeaderBearerMatches("POST /block HTTP/1.1\r\nX-FCG-Token: " + WriteToken + "\r\n\r\n", WriteToken));
    }

    [Fact]
    public void ApiTokenIsWriteSecretWhenBlockTokenUnset()
    {
        ListenHooks.Reset();
        ListenHooks.OverrideEnv = true;
        ListenHooks.Token = WriteToken;
        try
        {
            using (ListenHost host = ListenHost.Start(ChainSource()))
            {
                string none = ReadAll(host.Port, PostBlock("{\"text\":\"none\"}", null));
                Assert.StartsWith("HTTP/1.1 401 ", none);
                string ok = ReadAll(host.Port, PostBlock("{\"text\":\"via-api\"}", "Bearer " + WriteToken));
                Assert.StartsWith("HTTP/1.1 200 ", ok);
                Assert.Contains("via-api", GetChain(host.Port));
                string info = ReadAll(host.Port, "GET /info HTTP/1.1\r\nHost: x\r\n\r\n");
                Assert.StartsWith("HTTP/1.1 200 ", info);
            }
        }
        finally
        {
            ListenHooks.Reset();
        }
    }

    static string ChainSource()
    {
        string root = FindRoot();
        return File.ReadAllText(Path.Combine(root, "api", "fcgcpa.vire"));
    }

    static string GetChain(int port)
    {
        string raw = ReadAll(port, "GET /chain HTTP/1.1\r\nHost: x\r\n\r\n");
        int split = raw.IndexOf("\r\n\r\n", StringComparison.Ordinal);
        return split < 0 ? raw : raw.Substring(split + 4);
    }

    static string PostBlock(string json, string authorization)
    {
        string extra = authorization == null ? "" : "Authorization: " + authorization + "\r\n";
        return "POST /block HTTP/1.1\r\nHost: x\r\n" + extra + "Content-Length: " + Encoding.UTF8.GetByteCount(json) + "\r\n\r\n" + json;
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

    static string FindRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "api", "fcgcpa.vire"))) return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root");
    }
}
