using System;
using System.IO;
using System.Text;
using Xunit;

public class NativeParserFuzzTests
{
    const int Seed = 20261113;

    [Fact]
    public void HttpAndJsonFixedSeedNeverCrash()
    {
        int pid = Environment.ProcessId;
        var rng = new Random(Seed);
        for (int n = 0; n < 200; n++)
        {
            byte[] raw = NextHttp(rng);
            HttpWire.Result parsed = HttpWire.ParseComplete(raw, raw.Length);
            Assert.True(parsed.Status == 0 || parsed.Status >= 400, "status " + parsed.Status);
            Assert.Equal(pid, Environment.ProcessId);

            string json = NextJson(rng);
            try { Json.Read(json, 1); }
            catch (VireError) { }
            Assert.Equal(pid, Environment.ProcessId);
        }
    }

    [Fact]
    public void SourcesDeclareWxAtomicCrashLog()
    {
        string root = DualMode.FindRoot();
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        string more = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        string rt = File.ReadAllText(Path.Combine(root, "src", "rt.vire"));
        Assert.Contains("VirtualQuery", pe);
        Assert.Contains("MoveFileExA", pe);
        Assert.Contains("iat_mv", more);
        Assert.Contains("write_tmp_ok", more);
        Assert.Contains("crash_log_path", rt);
        Assert.Contains("crash_abs", rt);
        Assert.Contains("rt_crash_prepare", rt);
        Assert.Contains("rt_wx_check", rt);
        Assert.DoesNotContain("33554433", more);
        Assert.DoesNotContain("Set-MpPreference", File.ReadAllText(Path.Combine(root, "tools", "native-security-windows.ps1")));
    }

    static byte[] NextHttp(Random rng)
    {
        int kind = rng.Next(6);
        if (kind == 0) return Encoding.ASCII.GetBytes("GET / HTTP/1.1\r\nHost: x\r\n\r\n");
        if (kind == 1) return Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc");
        if (kind == 2) return Encoding.ASCII.GetBytes("GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n");
        if (kind == 3) return Encoding.ASCII.GetBytes("GET /" + new string('a', rng.Next(8, 200)) + " HTTP/1.1\r\nHost: x\r\n\r\n");
        if (kind == 4) return Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nHost: x\r\n\r\n");
        byte[] buf = new byte[rng.Next(4, 96)];
        rng.NextBytes(buf);
        return buf;
    }

    static string NextJson(Random rng)
    {
        string[] corpus = { "{}", "[]", "true", "null", "{\"ok\":true}", "{\"ok\":1}", "[1,2]", "\"hi\"" };
        int kind = rng.Next(4);
        if (kind == 0) return corpus[rng.Next(corpus.Length)];
        if (kind == 1)
        {
            char[] c = corpus[rng.Next(corpus.Length)].ToCharArray();
            if (c.Length > 0) c[rng.Next(c.Length)] = (char)rng.Next(32, 126);
            return new string(c);
        }
        var sb = new StringBuilder();
        int n = rng.Next(1, 40);
        for (int i = 0; i < n; i++) sb.Append((char)rng.Next(1, 127));
        return sb.ToString();
    }
}
