using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

/// <summary>
/// Deterministic LCG mutator shared by Track D FuzzTests and the campaign.
/// Seed 20261030 and the multiplier/addend match FuzzTests so old corpus runs stay replayable.
/// </summary>
static class FuzzCore
{
    public const int DefaultSeed = 20261030;
    public const int DefaultIters = 400;
    public const int MaxIters = 2000000;
    public const int MaxInput = 4096;
    public const int HangMs = 4000;

    public static int Iters()
    {
        string raw = Environment.GetEnvironmentVariable("VIRE_FUZZ_ITERS");
        if (string.IsNullOrWhiteSpace(raw)) return DefaultIters;
        int value;
        if (!int.TryParse(raw.Trim(), out value) || value < 1) return DefaultIters;
        if (value > MaxIters) value = MaxIters;
        return value;
    }

    public static int Seconds()
    {
        string raw = Environment.GetEnvironmentVariable("VIRE_FUZZ_SECONDS");
        if (string.IsNullOrWhiteSpace(raw)) return 0;
        int value;
        if (!int.TryParse(raw.Trim(), out value) || value < 0) return 0;
        if (value > 7200) value = 7200;
        return value;
    }

    public static int NativePeIters()
    {
        string raw = Environment.GetEnvironmentVariable("VIRE_FUZZ_NATIVE_ITERS");
        if (string.IsNullOrWhiteSpace(raw)) return 4;
        int value;
        if (!int.TryParse(raw.Trim(), out value) || value < 1) return 4;
        if (value > 64) value = 64;
        return value;
    }

    public static string RepoRoot()
    {
        return DualMode.FindRoot();
    }

    public static string CorpusDir()
    {
        return Path.Combine(RepoRoot(), "tests", "fuzz", "corpus");
    }

    public static string FindingsDir()
    {
        return Path.Combine(RepoRoot(), "tests", "fuzz", "findings");
    }

    public static string[] LoadCorpus(string pattern)
    {
        string dir = CorpusDir();
        if (!Directory.Exists(dir)) return new string[0];
        string[] files = Directory.GetFiles(dir, pattern);
        string[] texts = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            texts[i] = File.ReadAllText(files[i]);
        return texts;
    }

    public static string[] LoadGrammarSeeds()
    {
        List<string> texts = new List<string>();
        AddFiles(texts, CorpusDir(), "*.vire");
        AddFiles(texts, Path.Combine(RepoRoot(), "tests", "conformance"), "*.vire");
        AddFiles(texts, Path.Combine(RepoRoot(), "tests", "crash"), "*.vire");
        AddFiles(texts, Path.Combine(RepoRoot(), "tests", "native"), "*.vire");
        AddFiles(texts, Path.Combine(RepoRoot(), "samples"), "*.vire");
        string[] extras =
        {
            "greet.vire", "guest-hello.vire", "guest-strings.vire", "guest-expr.vire",
            "math.vire", "count.vire", "limits.vire"
        };
        for (int i = 0; i < extras.Length; i++)
        {
            string path = Path.Combine(RepoRoot(), extras[i]);
            if (File.Exists(path)) texts.Add(File.ReadAllText(path));
        }
        return texts.ToArray();
    }

    static void AddFiles(List<string> texts, string dir, string pattern)
    {
        if (!Directory.Exists(dir)) return;
        foreach (string file in Directory.GetFiles(dir, pattern))
        {
            string name = Path.GetFileName(file);
            if (name.StartsWith("deep-", StringComparison.Ordinal)) continue;
            FileInfo info = new FileInfo(file);
            if (info.Length > 200000) continue;
            texts.Add(File.ReadAllText(file));
        }
    }

    public static string MutateText(FuzzRng rng, string seed)
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

    public static string RandomSource(FuzzRng rng)
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

    public static string GrammarMutate(FuzzRng rng, string[] seeds)
    {
        int kind = rng.Next(8);
        if (kind == 0) return RandomSource(rng);
        if (kind == 1) return GrammarProgram(rng);
        if (seeds == null || seeds.Length == 0) return GrammarProgram(rng);
        string a = seeds[rng.Next(seeds.Length)];
        if (kind == 2) return MutateText(rng, a);
        if (kind == 3 && seeds.Length > 1)
        {
            string b = seeds[rng.Next(seeds.Length)];
            string splice = a + "\n" + b;
            if (splice.Length > MaxInput) splice = splice.Substring(0, MaxInput);
            return splice;
        }
        if (kind == 4) return NestInBlocks(rng, a);
        if (kind == 5) return InjectBuiltin(rng, a);
        if (kind == 6) return DropLines(rng, a);
        return MutateText(rng, GrammarProgram(rng) + "\n" + a);
    }

    public static string GrammarProgram(FuzzRng rng)
    {
        StringBuilder text = new StringBuilder();
        text.Append("define main\n");
        int stmts = 1 + rng.Next(12);
        int open = 0;
        for (int i = 0; i < stmts; i++)
        {
            int op = rng.Next(10);
            if (op == 0) { text.Append("  if 1\n"); open++; }
            else if (op == 1) { text.Append("  while 0\n"); open++; }
            else if (op == 2) { text.Append("  try\n"); open++; }
            else if (op == 3 && open > 0) { text.Append("  end\n"); open--; }
            else if (op == 4) text.Append("  say " + BuiltinExpr(rng) + "\n");
            else if (op == 5) text.Append("  let x" + rng.Next(8) + " be " + BuiltinExpr(rng) + "\n");
            else if (op == 6) text.Append("  parse with " + Quote(rng, JsonSnippet(rng)) + "\n");
            else if (op == 7) text.Append("  write with " + Quote(rng, PathSnippet(rng)) + ", " + Quote(rng, "x") + "\n");
            else if (op == 8) text.Append("  say (read with " + Quote(rng, PathSnippet(rng)) + ")\n");
            else text.Append("  say " + Quote(rng, "t" + rng.Next(99)) + " + " + Quote(rng, "u") + "\n");
        }
        while (open > 0) { text.Append("  end\n"); open--; }
        text.Append("end\n");
        return text.ToString();
    }

    static string NestInBlocks(FuzzRng rng, string seed)
    {
        int depth = 1 + rng.Next(8);
        StringBuilder text = new StringBuilder();
        text.Append("define wrap\n");
        for (int i = 0; i < depth; i++) text.Append("if 1\n");
        text.Append(seed);
        text.Append("\n");
        for (int i = 0; i < depth; i++) text.Append("end\n");
        text.Append("end\n");
        if (text.Length > MaxInput) return text.ToString().Substring(0, MaxInput);
        return text.ToString();
    }

    static string InjectBuiltin(FuzzRng rng, string seed)
    {
        string extra = "define extra\n  say " + BuiltinExpr(rng) + "\nend\n";
        string joined = extra + seed;
        if (joined.Length > MaxInput) return joined.Substring(0, MaxInput);
        return joined;
    }

    static string DropLines(FuzzRng rng, string seed)
    {
        string[] lines = seed.Replace("\r\n", "\n").Split('\n');
        if (lines.Length < 2) return MutateText(rng, seed);
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < lines.Length; i++)
        {
            if (rng.Next(5) == 0) continue;
            text.Append(lines[i]);
            text.Append('\n');
        }
        return text.ToString();
    }

    public static string BuiltinExpr(FuzzRng rng)
    {
        string[] forms =
        {
            "split with " + Quote(rng, "a,b,c") + ", " + Quote(rng, ","),
            "(" + Quote(rng, "hello") + " at " + rng.Next(8) + ")",
            "json with [1, 2, " + rng.Next(9) + "]",
            Quote(rng, "ab") + " + " + Quote(rng, "cd"),
            "text with " + rng.Next(100),
            "has with {\"k\":1}, " + Quote(rng, "k"),
            "length with " + Quote(rng, "abcd"),
            "push with [], " + rng.Next(5),
            "slice with " + Quote(rng, "abcdef") + ", 1, " + rng.Next(6),
            "join with [" + Quote(rng, "a") + ", " + Quote(rng, "b") + "], " + Quote(rng, ","),
            "parse with " + Quote(rng, JsonSnippet(rng)),
            "lower with " + Quote(rng, "AbC"),
            "replace with " + Quote(rng, "aa") + ", " + Quote(rng, "a") + ", " + Quote(rng, "b")
        };
        return forms[rng.Next(forms.Length)];
    }

    public static string JsonSnippet(FuzzRng rng)
    {
        int k = rng.Next(6);
        if (k == 0) return "null";
        if (k == 1) return "[1,2,3]";
        if (k == 2) return "{\"a\":1}";
        if (k == 3) return new string('[', 1 + rng.Next(20)) + new string(']', 1 + rng.Next(20));
        if (k == 4) return "\"" + new string('x', rng.Next(40)) + "\"";
        return "[true,false,null," + rng.Next(99) + "]";
    }

    public static string PathSnippet(FuzzRng rng)
    {
        string[] paths =
        {
            "data/note.txt", "site/app.js", "data/../etc/passwd", "../outside",
            "data/..\\secret", "CON.txt", "nul", "C:\\windows\\x", "/etc/passwd",
            "data/foo/../bar", "data/note.txt.", "data/note.txt ",
            "COM1.log", "foo<>bar", "data/ok.txt", "site/../data/x",
            "..\\..\\windows\\system32", "data/sub/file.txt", "\\\\?\\C:\\x"
        };
        if (rng.Next(4) == 0) return paths[rng.Next(paths.Length)] + "/" + rng.Next(9);
        return paths[rng.Next(paths.Length)];
    }

    static string Quote(FuzzRng rng, string inner)
    {
        if (rng.Next(20) == 0) return "\"" + inner.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\\0\"";
        return "\"" + inner.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }

    public static string MinimizeText(string source, Func<string, bool> stillBad)
    {
        if (source == null) return "";
        string cur = source;
        for (int round = 0; round < 24; round++)
        {
            bool cut = false;
            if (cur.Length > 2)
            {
                int mid = cur.Length / 2;
                string left = cur.Substring(0, mid);
                string right = cur.Substring(mid);
                if (left.Length > 0 && stillBad(left)) { cur = left; cut = true; }
                else if (right.Length > 0 && stillBad(right)) { cur = right; cut = true; }
            }
            if (!cut && cur.Length > 8)
            {
                int drop = Math.Max(1, cur.Length / 8);
                int at = cur.Length / 3;
                string next = cur.Remove(at, Math.Min(drop, cur.Length - at));
                if (next.Length > 0 && stillBad(next)) { cur = next; cut = true; }
            }
            if (!cut) break;
        }
        return cur;
    }

    public static FuzzFinding SaveFinding(string target, string kind, string classification, string rootCause, string body, string detail)
    {
        Directory.CreateDirectory(FindingsDir());
        string sha;
        using (SHA256 hasher = SHA256.Create())
        {
            byte[] hash = hasher.ComputeHash(Encoding.UTF8.GetBytes(body ?? ""));
            sha = BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }
        string stem = target + "-" + kind + "-" + sha.Substring(0, 12);
        string ext = target == "path" ? ".txt" : ".vire";
        string path = Path.Combine(FindingsDir(), stem + ext);
        File.WriteAllText(path, body ?? "");
        string meta = Path.Combine(FindingsDir(), stem + ".md");
        StringBuilder text = new StringBuilder();
        text.AppendLine("# " + stem);
        text.AppendLine();
        text.AppendLine("- target: `" + target + "`");
        text.AppendLine("- kind: `" + kind + "`");
        text.AppendLine("- classification: **" + classification + "**");
        text.AppendLine("- sha256: `" + sha + "`");
        text.AppendLine("- reproducer: `" + Rel(path) + "`");
        text.AppendLine("- seed: `" + DefaultSeed + "` (see campaign log for iteration)");
        text.AppendLine();
        text.AppendLine("## Root cause");
        text.AppendLine();
        text.AppendLine(rootCause);
        text.AppendLine();
        text.AppendLine("## Detail");
        text.AppendLine();
        text.AppendLine("```");
        text.AppendLine(detail ?? "");
        text.AppendLine("```");
        File.WriteAllText(meta, text.ToString());
        return new FuzzFinding(target, kind, classification, rootCause, Rel(path), sha, detail);
    }

    public static string Rel(string path)
    {
        string root = RepoRoot();
        if (path.StartsWith(root, StringComparison.Ordinal))
            return path.Substring(root.Length).TrimStart(Path.DirectorySeparatorChar, '/').Replace('\\', '/');
        return path.Replace('\\', '/');
    }

    public static bool IsExpectedGuest(Exception ex)
    {
        return ex is VireError || ex is HaltSignal || ex is ReturnSignal || ex is StopSignal || ex is SkipSignal;
    }

    public static string Classify(Exception ex, string target)
    {
        if (ex == null) return "robustness";
        if (ex is TimeoutException) return "robustness";
        string msg = ex.Message ?? "";
        if (target == "path" && msg.IndexOf("program folder", StringComparison.OrdinalIgnoreCase) < 0
            && msg.IndexOf("data or site", StringComparison.OrdinalIgnoreCase) < 0
            && !IsExpectedGuest(ex))
            return "security";
        if (ex is AccessViolationException || ex is SEHException) return "security";
        if (!IsExpectedGuest(ex) && !(ex is OutOfMemoryException) && !(ex is StackOverflowException))
            return "security";
        return "robustness";
    }
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

sealed class FuzzFinding
{
    public string Target;
    public string Kind;
    public string Classification;
    public string RootCause;
    public string Path;
    public string Sha256;
    public string Detail;

    public FuzzFinding(string target, string kind, string classification, string rootCause, string path, string sha256, string detail)
    {
        Target = target;
        Kind = kind;
        Classification = classification;
        RootCause = rootCause;
        Path = path;
        Sha256 = sha256;
        Detail = detail;
    }
}

sealed class FuzzStats
{
    public string Target;
    public long Executions;
    public double Seconds;
    public int Findings;
    public int Hangs;
    public int Crashes;

    public override string ToString()
    {
        return Target + ": executions=" + Executions + " seconds=" + Seconds.ToString("0.000")
            + " findings=" + Findings + " hangs=" + Hangs + " crashes=" + Crashes;
    }
}

sealed class FuzzLog
{
    public readonly List<FuzzFinding> Findings = new List<FuzzFinding>();
    public readonly List<FuzzStats> Stats = new List<FuzzStats>();

    public void Add(FuzzFinding finding)
    {
        if (finding == null) return;
        for (int i = 0; i < Findings.Count; i++)
            if (Findings[i].Sha256 == finding.Sha256 && Findings[i].Target == finding.Target) return;
        Findings.Add(finding);
    }

    public void WriteReport()
    {
        string path = Path.Combine(FuzzCore.RepoRoot(), "tests", "fuzz", "CAMPAIGN-RUN.md");
        StringBuilder text = new StringBuilder();
        text.AppendLine("# Fuzz campaign run");
        text.AppendLine();
        text.AppendLine("- tip: `227c0e0a22c817492d090fa2443ed9f264ecb644`");
        text.AppendLine("- host: " + Environment.OSVersion);
        text.AppendLine("- utc: " + DateTime.UtcNow.ToString("o"));
        text.AppendLine("- VIRE_FUZZ_ITERS: " + (Environment.GetEnvironmentVariable("VIRE_FUZZ_ITERS") ?? "(default " + FuzzCore.DefaultIters + ")"));
        text.AppendLine("- VIRE_FUZZ_SECONDS: " + (Environment.GetEnvironmentVariable("VIRE_FUZZ_SECONDS") ?? "0"));
        text.AppendLine();
        text.AppendLine("## Executions");
        text.AppendLine();
        text.AppendLine("| Target | Executions | Seconds | Findings | Hangs | Crashes |");
        text.AppendLine("|---|---:|---:|---:|---:|---:|");
        for (int i = 0; i < Stats.Count; i++)
        {
            FuzzStats s = Stats[i];
            text.AppendLine("| " + s.Target + " | " + s.Executions + " | " + s.Seconds.ToString("0.000") + " | " + s.Findings + " | " + s.Hangs + " | " + s.Crashes + " |");
        }
        text.AppendLine();
        text.AppendLine("## Findings");
        text.AppendLine();
        if (Findings.Count == 0) text.AppendLine("None this run.");
        for (int i = 0; i < Findings.Count; i++)
        {
            FuzzFinding f = Findings[i];
            text.AppendLine("- **" + f.Classification + "** `" + f.Target + "/" + f.Kind + "` `" + f.Sha256 + "` `" + f.Path + "` — " + f.RootCause);
        }
        File.WriteAllText(path, text.ToString());
    }
}
