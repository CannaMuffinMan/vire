using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

public class ChainTests : IDisposable
{
    ListenHost host;
    string folder;

    public ChainTests()
    {
        ListenHooks.Reset();
        string root = FindRoot();
        string source = File.ReadAllText(Path.Combine(root, "api", "fcgcpa.vire"));
        host = ListenHost.Start(source);
        folder = host.Folder;
    }

    public void Dispose()
    {
        ListenHooks.Reset();
        if (host != null) host.Dispose();
    }

    [Fact]
    public void ValidAppendAndRejectsForgedLinks()
    {
        using (HttpClient client = Client())
        {
            HttpResponseMessage ok = Post(client, "{\"text\":\"hello\"}");
            Assert.Equal(200, (int)ok.StatusCode);
            string body = ok.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            Assert.Contains("\"accepted\":true", body);

            HttpResponseMessage forged = Post(client, "{\"text\":\"x\",\"proof\":\"deadbeef\"}");
            Assert.Equal(400, (int)forged.StatusCode);

            HttpResponseMessage wrongPrev = Post(client, "{\"text\":\"y\",\"previous\":\"not-the-tip\"}");
            Assert.Equal(400, (int)wrongPrev.StatusCode);
        }
    }

    [Fact]
    public void TamperedSegmentRefusesWritesWith503()
    {
        using (HttpClient client = Client())
        {
            Assert.Equal(200, (int)Post(client, "{\"text\":\"keep\"}").StatusCode);
        }
        string seg = Path.Combine(folder, "data", "chain", "000001.json");
        string raw = File.ReadAllText(seg);
        File.WriteAllText(seg, raw.Replace("keep", "tamper"));
        using (HttpClient client = Client())
        {
            HttpResponseMessage res = Post(client, "{\"text\":\"more\"}");
            Assert.Equal(503, (int)res.StatusCode);
            string body = res.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            Assert.Contains("chain invalid", body);
        }
    }

    [Fact]
    public void SegmentRotatesAt512KbAndNeverExceedsIt()
    {
        using (HttpClient client = Client())
        {
            string chunk = new string('a', 4000);
            for (int i = 0; i < 200; i++)
            {
                HttpResponseMessage res = Post(client, "{\"text\":" + Json.Write(chunk) + "}");
                string reply = res.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                Assert.True((int)res.StatusCode == 200, "rotate post " + i + " => " + (int)res.StatusCode + " " + reply);
                if (File.Exists(Path.Combine(folder, "data", "chain", "000002.json")))
                    break;
            }
        }
        Assert.True(File.Exists(Path.Combine(folder, "data", "chain", "000002.json")));
        long largest = 0;
        foreach (string file in Directory.GetFiles(Path.Combine(folder, "data", "chain"), "*.json"))
        {
            long len = new FileInfo(file).Length;
            if (Path.GetFileName(file) == "head.json") continue;
            Assert.True(len <= 524288, Path.GetFileName(file) + " is " + len);
            if (len > largest) largest = len;
        }
        Assert.True(largest > 0);
    }

    [Fact]
    public void PastSegmentCapReturns507()
    {
        host.Dispose();
        host = null;
        string root = FindRoot();
        string source = File.ReadAllText(Path.Combine(root, "api", "fcgcpa.vire"));
        string work = Path.Combine(Path.GetTempPath(), "vire-chain-full-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(work, "data", "chain"));
        WriteFullChain(Path.Combine(work, "data", "chain"));
        File.WriteAllText(Path.Combine(work, "listen.vire"), source);
        Dictionary<string, Func> funcs = Program.Load(Path.Combine(work, "listen.vire"), work, new HashSet<string>());
        Machine machine = new Machine(funcs, work);
        machine.UseBudget(5000000);
        CancellationTokenSource cts = new CancellationTokenSource();
        Thread thread = new Thread(() => machine.ListenCore(0, 1, cts.Token));
        thread.IsBackground = true;
        thread.Start();
        DateTime until = DateTime.UtcNow.AddSeconds(5);
        while (machine.ListenPort == 0 && DateTime.UtcNow < until) Thread.Sleep(10);
        int port = machine.ListenPort;
        PortGuard.AssertAllowedPort(port);
        try
        {
            using (HttpClient client = new HttpClient())
            {
                client.Timeout = TimeSpan.FromSeconds(30);
                HttpResponseMessage res = client.PostAsync("http://127.0.0.1:" + port + "/block",
                    new StringContent("{\"text\":\"overflow\"}", Encoding.UTF8, "application/json")).GetAwaiter().GetResult();
                string reply = res.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                Assert.True((int)res.StatusCode == 507, "got " + (int)res.StatusCode + " " + reply);
            }
        }
        finally
        {
            cts.Cancel();
            thread.Join(8000);
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void FiftyConcurrentPostsAreConsecutive()
    {
        Task<int>[] jobs = new Task<int>[50];
        using (HttpClient client = Client())
        {
            for (int i = 0; i < 50; i++)
            {
                int n = i;
                jobs[i] = Task.Run(() =>
                {
                    HttpResponseMessage res = client.PostAsync("http://127.0.0.1:" + host.Port + "/block",
                        new StringContent("{\"text\":\"c" + n + "\"}", Encoding.UTF8, "application/json")).GetAwaiter().GetResult();
                    Assert.Equal(200, (int)res.StatusCode);
                    string body = res.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                    int at = body.IndexOf("\"index\":", StringComparison.Ordinal);
                    Assert.True(at >= 0);
                    int end = at + 8;
                    while (end < body.Length && char.IsDigit(body[end])) end++;
                    return int.Parse(body.Substring(at + 8, end - (at + 8)));
                });
            }
            Assert.True(Task.WaitAll(jobs, TimeSpan.FromSeconds(60)), "concurrent posts hung");
        }
        List<int> indexes = new List<int>();
        for (int i = 0; i < jobs.Length; i++) indexes.Add(jobs[i].GetAwaiter().GetResult());
        indexes.Sort();
        Assert.Equal(50, indexes.Count);
        for (int i = 0; i < 50; i++)
            Assert.Equal(i + 1, indexes[i]);
        using (HttpClient client = Client())
        {
            HttpResponseMessage chain = client.GetAsync("http://127.0.0.1:" + host.Port + "/chain").GetAwaiter().GetResult();
            Assert.Equal(200, (int)chain.StatusCode);
            object parsed = Json.Read(chain.Content.ReadAsStringAsync().GetAwaiter().GetResult(), 1);
            List<object> blocks = parsed as List<object>;
            Assert.NotNull(blocks);
            Assert.Equal(51, blocks.Count);
        }
    }

    HttpClient Client()
    {
        HttpClient client = new HttpClient();
        client.Timeout = TimeSpan.FromSeconds(30);
        client.BaseAddress = new Uri("http://127.0.0.1:" + host.Port + "/");
        return client;
    }

    HttpResponseMessage Post(HttpClient client, string json)
    {
        return client.PostAsync("http://127.0.0.1:" + host.Port + "/block",
            new StringContent(json, Encoding.UTF8, "application/json")).GetAwaiter().GetResult();
    }

    static string ProofOf(int index, string previous, string text)
    {
        List<object> row = new List<object>();
        row.Add(index);
        row.Add(previous);
        row.Add(text);
        return VireSeal.HashText(Json.Write(row));
    }

    static void WriteFullChain(string dir)
    {
        string previous = "0";
        int index = 0;
        for (int seg = 1; seg <= 64; seg++)
        {
            string link = previous;
            StringBuilder json = new StringBuilder();
            json.Append("{\"link\":");
            json.Append(Json.Write(link));
            json.Append(",\"blocks\":[");
            bool first = true;
            int target = seg == 64 ? 524288 : 0;
            while (true)
            {
                string text = seg == 64 ? new string('z', 200) : "s" + seg;
                string proof = ProofOf(index, previous, text);
                Dictionary<string, object> block = new Dictionary<string, object>();
                block["index"] = index;
                block["previous"] = previous;
                block["proof"] = proof;
                block["text"] = text;
                string piece = Json.Write(block);
                if (!first) json.Append(',');
                first = false;
                json.Append(piece);
                previous = proof;
                index++;
                if (seg != 64) break;
                if (json.Length >= target) break;
            }
            json.Append("]}");
            string name = seg.ToString().PadLeft(6, '0') + ".json";
            File.WriteAllText(Path.Combine(dir, name), json.ToString());
        }
        Dictionary<string, object> head = new Dictionary<string, object>();
        head["segment"] = 64;
        head["index"] = index - 1;
        head["proof"] = previous;
        File.WriteAllText(Path.Combine(dir, "head.json"), Json.Write(head));
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
