using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Xunit;

public class FuzzTests
{
    const int Seed = 20261030;
    const int DefaultIters = 400;
    const int MaxInput = 4096;

    [Fact]
    public void LexerParserSeededFuzzNeverCrashes()
    {
        int pid = Environment.ProcessId;
        FuzzRng rng = new FuzzRng(Seed);
        string[] corpus = LoadCorpus("*.vire");
        int iters = Iters();
        for (int n = 0; n < iters; n++)
        {
            string source = NextText(rng, corpus);
            try
            {
                List<Token> tokens = Lexer.Tokenize(source);
                new Parser(tokens).Parse();
            }
            catch (VireError)
            {
            }
            Assert.Equal(pid, Environment.ProcessId);
        }
    }

    [Fact]
    public void SealLoaderSeededFuzzRejectsAndFailsClosed()
    {
        int pid = Environment.ProcessId;
        WithKey(() =>
        {
            byte[] good = VireSeal.SealBytes(Encoding.UTF8.GetBytes("{\"funcs\":[]}"));
            FuzzRng rng = new FuzzRng(Seed ^ 7);
            int iters = Iters();
            for (int n = 0; n < iters; n++)
            {
                byte[] mutated = MutateBytes(rng, good);
                try
                {
                    Dictionary<string, object> funcs = CompiledProgram.LoadFuncs(mutated);
                    Assert.NotNull(funcs);
                }
                catch (VireError err)
                {
                    Assert.DoesNotContain("internal error", err.Message);
                }
                Assert.Equal(pid, Environment.ProcessId);
            }

            byte[] truncated = new byte[Math.Max(1, good.Length / 2)];
            Array.Copy(good, truncated, truncated.Length);
            Assert.Throws<VireError>(() => CompiledProgram.LoadFuncs(truncated));

            byte[] forged = (byte[])good.Clone();
            if (forged.Length > 20) forged[20] ^= 0x5a;
            Assert.Throws<VireError>(() => CompiledProgram.LoadFuncs(forged));
        });
    }

    [Fact]
    public void JsonSeededFuzzHonorsDepthAndSize()
    {
        int pid = Environment.ProcessId;
        FuzzRng rng = new FuzzRng(Seed ^ 13);
        string[] corpus = LoadCorpus("*.json");
        int iters = Iters();
        for (int n = 0; n < iters; n++)
        {
            string text = NextText(rng, corpus);
            try { Json.Read(text, 1); }
            catch (VireError) { }
            Assert.Equal(pid, Environment.ProcessId);
        }
    }

    [Fact]
    public void ListenRequestParseSeededFuzzNeverCrashes()
    {
        int pid = Environment.ProcessId;
        FuzzRng rng = new FuzzRng(Seed ^ 21);
        string[] corpus = LoadCorpus("http-*.txt");
        int iters = Iters();
        for (int n = 0; n < iters; n++)
        {
            byte[] raw = Encoding.UTF8.GetBytes(NextText(rng, corpus));
            HttpWire.Result parsed = HttpWire.ParseComplete(raw, raw.Length);
            Assert.True(parsed.Status == 0 || parsed.Status >= 400);
            if (parsed.Status == 0)
            {
                Assert.False(string.IsNullOrEmpty(parsed.Method));
                Assert.False(string.IsNullOrEmpty(parsed.Path));
                Assert.True(parsed.ContentLength <= HttpWire.MaxRequestBody);
                Assert.True(parsed.Head.Length <= HttpWire.MaxHeaderBlock);
            }
            Assert.Equal(pid, Environment.ProcessId);
        }

        byte[] hugeLine = Encoding.ASCII.GetBytes("GET /" + new string('a', HttpWire.MaxRequestLine + 8) + " HTTP/1.1\r\nHost: x\r\n\r\n");
        Assert.Equal(431, HttpWire.ParseComplete(hugeLine, hugeLine.Length).Status);

        byte[] hugeHead = Encoding.ASCII.GetBytes("GET / HTTP/1.1\r\n" + new string('H', HttpWire.MaxHeaderBlock) + ": x\r\n\r\n");
        int headStatus = HttpWire.ParseComplete(hugeHead, Math.Min(hugeHead.Length, HttpWire.MaxHeaderBlock)).Status;
        Assert.True(headStatus == 431 || headStatus == 408, "headers status " + headStatus);

        string fatBody = "POST / HTTP/1.1\r\nContent-Length: " + (HttpWire.MaxRequestBody + 1) + "\r\n\r\n";
        byte[] fat = Encoding.ASCII.GetBytes(fatBody);
        Assert.Equal(413, HttpWire.ParseComplete(fat, fat.Length).Status);

        byte[] chunked = Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n");
        Assert.Equal(501, HttpWire.ParseComplete(chunked, chunked.Length).Status);

        byte[] noLen = Encoding.ASCII.GetBytes("POST / HTTP/1.1\r\nHost: x\r\n\r\n");
        Assert.Equal(411, HttpWire.ParseComplete(noLen, noLen.Length).Status);
    }

    [Fact]
    public void FuzzCorpusSeedsStayTextOnly()
    {
        string dir = CorpusDir();
        foreach (string path in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
        {
            string ext = Path.GetExtension(path).ToLowerInvariant();
            Assert.True(ext == ".vire" || ext == ".json" || ext == ".txt", path);
        }
    }

    static int Iters()
    {
        string raw = Environment.GetEnvironmentVariable("VIRE_FUZZ_ITERS");
        if (string.IsNullOrWhiteSpace(raw)) return DefaultIters;
        int value;
        if (!int.TryParse(raw.Trim(), out value) || value < 1) return DefaultIters;
        if (value > 200000) value = 200000;
        return value;
    }

    static string NextText(FuzzRng rng, string[] corpus)
    {
        int kind = rng.Next(6);
        if (kind == 0) return RandomSource(rng);
        if (kind == 1 && corpus.Length > 0) return MutateText(rng, corpus[rng.Next(corpus.Length)]);
        if (kind == 2) return RandomJson(rng);
        if (kind == 3) return RandomHttp(rng);
        if (corpus.Length == 0) return RandomSource(rng);
        string a = corpus[rng.Next(corpus.Length)];
        if (kind == 4 && corpus.Length > 1)
            return (a + corpus[rng.Next(corpus.Length)]).Substring(0, Math.Min(MaxInput, a.Length + 8));
        return MutateText(rng, a);
    }

    static string RandomSource(FuzzRng rng)
    {
        int len = rng.Next(MaxInput);
        StringBuilder text = new StringBuilder(len);
        string alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ \n\"'~+-*/%<>=()[]{}:,.";
        for (int i = 0; i < len; i++)
        {
            if (rng.Next(30) == 0) text.Append((char)rng.Next(256));
            else text.Append(alphabet[rng.Next(alphabet.Length)]);
        }
        return text.ToString();
    }

    static string RandomJson(FuzzRng rng)
    {
        if (rng.Next(8) == 0) return new string('[', 1 + rng.Next(80)) + new string(']', 1 + rng.Next(80));
        if (rng.Next(6) == 0) return "\"" + new string('a', rng.Next(200)) + "\"";
        return MutateText(rng, "{\"k\":[1,true,null]}");
    }

    static string RandomHttp(FuzzRng rng)
    {
        string[] methods = { "GET", "POST", "PUT", "HEAD", "PATCH", "OPTIONS", "TRACE", "" };
        string method = methods[rng.Next(methods.Length)];
        string path = rng.Next(5) == 0 ? "/../x" : "/" + new string('a', rng.Next(40));
        StringBuilder text = new StringBuilder();
        text.Append(method);
        text.Append(' ');
        text.Append(path);
        text.Append(" HTTP/1.1\r\n");
        int headers = rng.Next(8);
        for (int i = 0; i < headers; i++)
            text.Append("H" + i + ": " + rng.Next(1000) + "\r\n");
        if (rng.Next(2) == 0) text.Append("Content-Length: " + rng.Next(50) + "\r\n");
        if (rng.Next(8) == 0) text.Append("Transfer-Encoding: chunked\r\n");
        text.Append("\r\n");
        text.Append(new string('x', rng.Next(80)));
        return text.ToString();
    }

    static string MutateText(FuzzRng rng, string seed)
    {
        char[] chars = seed.ToCharArray();
        if (chars.Length == 0) return RandomSource(rng);
        int flips = 1 + rng.Next(8);
        for (int i = 0; i < flips; i++)
        {
            int at = rng.Next(chars.Length);
            int op = rng.Next(4);
            if (op == 0) chars[at] = (char)rng.Next(128);
            else if (op == 1) chars[at] = (char)(chars[at] ^ (char)(1 + rng.Next(127)));
            else if (op == 2 && at + 1 < chars.Length) chars[at] = chars[at + 1];
            else chars[at] = '"';
        }
        if (rng.Next(4) == 0)
            return new string(chars, 0, Math.Max(1, rng.Next(chars.Length)));
        return new string(chars);
    }

    static byte[] MutateBytes(FuzzRng rng, byte[] seed)
    {
        if (seed == null || seed.Length == 0) return new byte[] { (byte)rng.Next(256) };
        int op = rng.Next(5);
        if (op == 0)
        {
            byte[] cut = new byte[Math.Max(1, rng.Next(seed.Length))];
            Array.Copy(seed, cut, cut.Length);
            return cut;
        }
        byte[] copy = (byte[])seed.Clone();
        int flips = 1 + rng.Next(Math.Min(16, copy.Length));
        for (int i = 0; i < flips; i++)
            copy[rng.Next(copy.Length)] ^= (byte)(1 + rng.Next(255));
        if (op == 1)
        {
            byte[] grown = new byte[copy.Length + rng.Next(24)];
            Array.Copy(copy, grown, copy.Length);
            return grown;
        }
        return copy;
    }

    static string[] LoadCorpus(string pattern)
    {
        string dir = CorpusDir();
        if (!Directory.Exists(dir)) return new string[0];
        string[] files = Directory.GetFiles(dir, pattern);
        string[] texts = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            texts[i] = File.ReadAllText(files[i]);
        return texts;
    }

    static string CorpusDir()
    {
        return Path.Combine(RepoRoot(), "tests", "fuzz", "corpus");
    }

    static void WithKey(Action body)
    {
        string previous = Environment.GetEnvironmentVariable("VIRE_SEAL_KEY");
        byte[] key = new byte[32];
        for (int i = 0; i < key.Length; i++) key[i] = (byte)(i + 3);
        Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", Convert.ToBase64String(key));
        VireSeal.ClearKey();
        try
        {
            VireSeal.LoadFromEnvironment();
            body();
        }
        finally
        {
            VireSeal.ClearKey();
            Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", previous);
        }
    }

    static string RepoRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "tests.vire"))) return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root");
    }

    sealed class FuzzRng
    {
        uint state;

        public FuzzRng(int seed)
        {
            state = (uint)seed;
            if (state == 0) state = 0xA341316Cu;
        }

        public int Next(int max)
        {
            if (max <= 0) return 0;
            state = state * 1664525u + 1013904223u;
            return (int)(state % (uint)max);
        }
    }
}
