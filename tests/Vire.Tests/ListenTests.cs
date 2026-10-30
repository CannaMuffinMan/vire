using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

public class ListenTests : IDisposable
{
    ListenHost host;

    public ListenTests()
    {
        ListenHooks.Reset();
        host = ListenHost.Start(HandlerSource());
    }

    public void Dispose()
    {
        ListenHooks.Reset();
        if (host != null) host.Dispose();
    }

    [Fact]
    public void SequentialRequestsEachGetAFreshBudget()
    {
        using (HttpClient client = Http())
        {
            for (int i = 0; i < 10000; i++)
            {
                HttpResponseMessage res = client.GetAsync("http://127.0.0.1:" + host.Port + "/").Result;
                Assert.Equal(200, (int)res.StatusCode);
                Assert.Equal("no-store", res.Headers.CacheControl.ToString().Replace(" ", ""));
                Assert.Contains("nosniff", string.Join(" ", res.Headers.GetValues("X-Content-Type-Options")));
            }
        }
    }

    [Fact]
    public void SlowlorisTimesOutWithoutBlockingANormalClient()
    {
        using (TcpClient slow = new TcpClient())
        {
            slow.Connect("127.0.0.1", host.Port);
            NetworkStream stream = slow.GetStream();
            byte[] one = Encoding.ASCII.GetBytes("G");
            stream.Write(one, 0, 1);
            DateTime started = DateTime.UtcNow;
            Thread poke = new Thread(() =>
            {
                try
                {
                    while ((DateTime.UtcNow - started).TotalSeconds < 6)
                    {
                        Thread.Sleep(1000);
                        stream.Write(one, 0, 1);
                    }
                }
                catch (Exception) { }
            });
            poke.IsBackground = true;
            poke.Start();

            using (HttpClient client = Http())
            {
                DateTime t0 = DateTime.UtcNow;
                HttpResponseMessage res = client.GetAsync("http://127.0.0.1:" + host.Port + "/").Result;
                Assert.Equal(200, (int)res.StatusCode);
                Assert.True((DateTime.UtcNow - t0).TotalSeconds < 1.0, "normal client waited too long");
            }

            int slowCode = ReadStatus(slow, TimeSpan.FromSeconds(8));
            Assert.True(slowCode == 408 || slowCode == 0, "slow client code " + slowCode);
            Assert.True((DateTime.UtcNow - started).TotalSeconds <= 7);
        }
    }

    [Fact]
    public void CapacityIsBoundedAndDoesNotHang()
    {
        int workers;
        int iocp;
        ThreadPool.GetMinThreads(out workers, out iocp);
        ThreadPool.SetMinThreads(Math.Max(workers, 128), Math.Max(iocp, 128));
        TcpClient[] held = new TcpClient[64];
        try
        {
            for (int i = 0; i < 64; i++)
            {
                held[i] = new TcpClient();
                held[i].Connect("127.0.0.1", host.Port);
                NetworkStream stream = held[i].GetStream();
                byte[] partial = Encoding.ASCII.GetBytes("GET / HTTP/1.1\r\nHost: x\r\n");
                stream.Write(partial, 0, partial.Length);
            }
            Thread.Sleep(200);

            using (TcpClient extra = new TcpClient())
            {
                extra.ReceiveTimeout = 3000;
                extra.Connect("127.0.0.1", host.Port);
                byte[] req = Encoding.ASCII.GetBytes("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
                extra.GetStream().Write(req, 0, req.Length);
                int code = ReadStatus(extra, TimeSpan.FromSeconds(3));
                Assert.True(code == 503 || code == 200, "unexpected " + code);
            }
        }
        finally
        {
            for (int i = 0; i < held.Length; i++)
                if (held[i] != null) held[i].Close();
        }

        Task<int>[] burst = new Task<int>[80];
        for (int i = 0; i < burst.Length; i++)
        {
            burst[i] = Task.Run(() =>
            {
                using (HttpClient client = Http())
                {
                    HttpResponseMessage res = client.GetAsync("http://127.0.0.1:" + host.Port + "/").GetAwaiter().GetResult();
                    return (int)res.StatusCode;
                }
            });
        }
        Assert.True(Task.WaitAll(burst, TimeSpan.FromSeconds(20)), "parallel clients hung");
        int ok = 0;
        int busy = 0;
        for (int i = 0; i < burst.Length; i++)
        {
            int code = burst[i].GetAwaiter().GetResult();
            Assert.True(code == 200 || code == 503, "unexpected " + code);
            if (code == 200) ok++;
            if (code == 503) busy++;
        }
        Assert.True(ok >= 64 || busy >= 1, "expected 64 successes or at least one 503");
    }

    [Fact]
    public void InfiniteHandlerIs503ThenTheNextRequestIs200()
    {
        using (HttpClient client = Http())
        {
            HttpResponseMessage loop = client.GetAsync("http://127.0.0.1:" + host.Port + "/loop").Result;
            Assert.Equal(503, (int)loop.StatusCode);
            HttpResponseMessage ok = client.GetAsync("http://127.0.0.1:" + host.Port + "/").Result;
            Assert.Equal(200, (int)ok.StatusCode);
        }
    }

    [Fact]
    public void ListenerRejectsThroughHttpWire()
    {
        using (TcpClient emptyMethod = new TcpClient())
        {
            emptyMethod.Connect("127.0.0.1", host.Port);
            byte[] raw = Encoding.ASCII.GetBytes(" / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
            emptyMethod.GetStream().Write(raw, 0, raw.Length);
            Assert.Equal(400, ReadStatus(emptyMethod, TimeSpan.FromSeconds(5)));
            Assert.Equal(400, HttpWire.ParseComplete(raw, raw.Length).Status);
        }

        using (TcpClient hugeLine = new TcpClient())
        {
            hugeLine.Connect("127.0.0.1", host.Port);
            byte[] raw = Encoding.ASCII.GetBytes("GET /" + new string('a', HttpWire.MaxRequestLine + 8) + " HTTP/1.1\r\nHost: x\r\n\r\n");
            hugeLine.GetStream().Write(raw, 0, raw.Length);
            Assert.Equal(431, ReadStatus(hugeLine, TimeSpan.FromSeconds(5)));
            Assert.Equal(431, HttpWire.ParseComplete(raw, raw.Length).Status);
        }

        using (TcpClient fat = new TcpClient())
        {
            fat.Connect("127.0.0.1", host.Port);
            byte[] raw = Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nContent-Length: " + (HttpWire.MaxRequestBody + 1) + "\r\n\r\n");
            fat.GetStream().Write(raw, 0, raw.Length);
            Assert.Equal(413, ReadStatus(fat, TimeSpan.FromSeconds(5)));
            Assert.Equal(413, HttpWire.ParseComplete(raw, raw.Length).Status);
        }

        using (TcpClient chunked = new TcpClient())
        {
            chunked.Connect("127.0.0.1", host.Port);
            byte[] raw = Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n");
            chunked.GetStream().Write(raw, 0, raw.Length);
            Assert.Equal(501, ReadStatus(chunked, TimeSpan.FromSeconds(5)));
            Assert.Equal(501, HttpWire.ParseComplete(raw, raw.Length).Status);
        }
    }

    [Fact]
    public void TwoMegabyteBodyIs413()
    {
        using (TcpClient client = new TcpClient())
        {
            client.Connect("127.0.0.1", host.Port);
            NetworkStream stream = client.GetStream();
            byte[] head = Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 2097152\r\n\r\n");
            stream.Write(head, 0, head.Length);
            byte[] chunk = new byte[4096];
            stream.Write(chunk, 0, chunk.Length);
            int code = ReadStatus(client, TimeSpan.FromSeconds(5));
            Assert.Equal(413, code);
        }
    }

    [Fact]
    public void NonVireExceptionIs500AndTheServerStaysUp()
    {
        ListenHooks.RouteException = new InvalidOperationException("handler boom");
        using (HttpClient client = Http())
        {
            HttpResponseMessage boom = client.GetAsync("http://127.0.0.1:" + host.Port + "/boom").Result;
            Assert.Equal(500, (int)boom.StatusCode);
            string text = boom.Content.ReadAsStringAsync().Result;
            Assert.Contains("route failed", text);
            Assert.DoesNotContain("handler boom", text);
            HttpResponseMessage ok = client.GetAsync("http://127.0.0.1:" + host.Port + "/").Result;
            Assert.Equal(200, (int)ok.StatusCode);
        }
    }

    static HttpClient Http()
    {
        HttpClient client = new HttpClient();
        client.Timeout = TimeSpan.FromSeconds(15);
        return client;
    }

    static int ReadStatus(TcpClient client, TimeSpan wait)
    {
        client.ReceiveTimeout = (int)wait.TotalMilliseconds;
        try
        {
            NetworkStream stream = client.GetStream();
            byte[] buf = new byte[512];
            int n = stream.Read(buf, 0, buf.Length);
            if (n <= 0) return 0;
            string text = Encoding.ASCII.GetString(buf, 0, n);
            int space = text.IndexOf(' ');
            if (space < 0) return 0;
            int next = text.IndexOf(' ', space + 1);
            if (next < 0) next = text.IndexOf('\r');
            if (next < 0) return 0;
            int code;
            if (!int.TryParse(text.Substring(space + 1, next - space - 1), out code)) return 0;
            return code;
        }
        catch (IOException) { return 0; }
        catch (SocketException) { return 0; }
    }

    static string HandlerSource()
    {
        return string.Join("\n", new string[]
        {
            "define burn",
            "  let n be 0",
            "  while n < 80",
            "    let n be n + 1",
            "  end",
            "end",
            "define route with method, path, body",
            "  if path == \"/loop\"",
            "    while 1 == 1",
            "    end",
            "  end",
            "  burn",
            "  return \"{\\\"ok\\\":true}\"",
            "end",
            "define main",
            "  listen with 0",
            "end",
            ""
        });
    }
}

sealed class ListenHost : IDisposable
{
    public int Port;
    public string Folder;
    CancellationTokenSource cts;
    Thread thread;
    string folder;

    public static ListenHost Start(string source)
    {
        ListenHost host = new ListenHost();
        host.folder = Path.Combine(Path.GetTempPath(), "vire-listen-" + Guid.NewGuid().ToString("N"));
        host.Folder = host.folder;
        Directory.CreateDirectory(host.folder);
        Directory.CreateDirectory(Path.Combine(host.folder, "data"));
        string program = Path.Combine(host.folder, "listen.vire");
        File.WriteAllText(program, source);
        Dictionary<string, Func> funcs = Program.Load(program, host.folder, new HashSet<string>());
        Machine machine = new Machine(funcs, host.folder);
        machine.UseBudget(5000000);
        host.cts = new CancellationTokenSource();
        host.thread = new Thread(() => machine.ListenCore(0, 1, host.cts.Token));
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
