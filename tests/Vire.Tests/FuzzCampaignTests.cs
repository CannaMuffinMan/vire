using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using Xunit;

public class FuzzCampaignTests
{
    static readonly FuzzLog Log = new FuzzLog();

    [Fact]
    public void HardLimitsStayAtDocumentedCaps()
    {
        Assert.Equal(5000000, Program.ProgramStepCap);
        Assert.Equal(64, new Budget().MaxCalls);
        Assert.Contains("33554432", File.ReadAllText(Path.Combine(FuzzCore.RepoRoot(), "src", "rt.vire")));
        Assert.Contains("100000", File.ReadAllText(Path.Combine(FuzzCore.RepoRoot(), "docs", "native-limits.md")));
        Assert.DoesNotContain("MaxCalls = 128", File.ReadAllText(Path.Combine(FuzzCore.RepoRoot(), "Vire.cs")));
    }

    [Fact]
    public void CampaignTargetsRunDeterministically()
    {
        string only = Environment.GetEnvironmentVariable("VIRE_FUZZ_ONLY") ?? "";
        if (only.Length == 0 || only == "frontend")
            RunTimed("frontend", FuzzCore.SeedFor("frontend"), DriveFrontend);
        if (only.Length == 0 || only == "builtins")
            RunTimed("builtins", FuzzCore.SeedFor("builtins"), DriveBuiltins);
        if (only.Length == 0 || only == "gc")
            RunTimed("gc", FuzzCore.SeedFor("gc"), DriveGc);
        if (only.Length == 0 || only == "path")
            RunTimed("path", FuzzCore.SeedFor("path"), DrivePaths);
        Log.WriteReport();
        foreach (FuzzFinding finding in Log.Findings)
            Console.WriteLine("FINDING " + finding.Classification + " " + finding.Path + " " + finding.RootCause);
    }

    static void RunTimed(string target, int seed, Action<FuzzRng, FuzzStats> body)
    {
        int pid = Environment.ProcessId;
        FuzzRng rng = new FuzzRng(seed);
        FuzzStats stats = new FuzzStats();
        stats.Target = target;
        stats.Seed = seed;
        Environment.SetEnvironmentVariable("VIRE_FUZZ_LAST_SEED", seed.ToString());
        int seconds = FuzzCore.Seconds();
        int cap = seconds > 0 ? FuzzCore.MaxIters : FuzzCore.Iters();
        Stopwatch clock = Stopwatch.StartNew();
        int n = 0;
        while (n < cap)
        {
            if (seconds > 0 && clock.Elapsed.TotalSeconds >= seconds) break;
            body(rng, stats);
            n++;
            stats.Executions = n;
            Assert.Equal(pid, Environment.ProcessId);
        }
        stats.Seconds = clock.Elapsed.TotalSeconds;
        Log.Stats.Add(stats);
        Console.WriteLine(stats.ToString());
    }

    static void DriveFrontend(FuzzRng rng, FuzzStats stats)
    {
        string[] seeds = FuzzCore.LoadGrammarSeeds();
        string source = FuzzCore.GrammarMutate(rng, seeds);
        Stopwatch one = Stopwatch.StartNew();
        try
        {
            List<Token> tokens = Lexer.Tokenize(source);
            Unit unit = new Parser(tokens).Parse();
            if (unit != null && unit.Funcs.ContainsKey("main") && rng.Next(3) == 0)
                RunGuest(source, 20000);
        }
        catch (Exception ex)
        {
            Note(stats, "frontend", source, ex, one.ElapsedMilliseconds);
        }
        if (one.ElapsedMilliseconds > FuzzCore.HangMs)
            NoteHang(stats, "frontend", source, one.ElapsedMilliseconds);
    }

    static void DriveBuiltins(FuzzRng rng, FuzzStats stats)
    {
        string source = BuiltinProgram(rng);
        Stopwatch one = Stopwatch.StartNew();
        try
        {
            RunGuest(source, 200000);
            ProbeBuiltinDirect(rng);
        }
        catch (Exception ex)
        {
            Note(stats, "builtins", source, ex, one.ElapsedMilliseconds);
        }
        if (one.ElapsedMilliseconds > FuzzCore.HangMs)
            NoteHang(stats, "builtins", source, one.ElapsedMilliseconds);
    }

    static void DriveGc(FuzzRng rng, FuzzStats stats)
    {
        string source = GcProgram(rng);
        Stopwatch one = Stopwatch.StartNew();
        try
        {
            int code = RunGuest(source, 5000000);
            if (code < 0 || code > 2)
            {
                Note(stats, "gc", source, new InvalidOperationException("exit " + code), one.ElapsedMilliseconds);
            }
        }
        catch (Exception ex)
        {
            Note(stats, "gc", source, ex, one.ElapsedMilliseconds);
        }
        if (one.ElapsedMilliseconds > FuzzCore.HangMs)
            NoteHang(stats, "gc", source, one.ElapsedMilliseconds);
    }

    static void DrivePaths(FuzzRng rng, FuzzStats stats)
    {
        string root = Path.Combine(Path.GetTempPath(), "vire-fuzz-path-" + Environment.ProcessId);
        Directory.CreateDirectory(Path.Combine(root, "data"));
        Directory.CreateDirectory(Path.Combine(root, "site"));
        File.WriteAllText(Path.Combine(root, "data", "ok.txt"), "inside");
        string outside = Path.Combine(Path.GetTempPath(), "vire-fuzz-outside-" + Environment.ProcessId + ".txt");
        File.WriteAllText(outside, "secret");
        string link = Path.Combine(root, "data", "link.txt");
        try
        {
            if (File.Exists(link)) File.Delete(link);
            File.CreateSymbolicLink(link, outside);
        }
        catch (Exception)
        {
        }
        string probe = FuzzCore.PathSnippet(rng);
        if (rng.Next(6) == 0) probe = MutatePath(rng, probe);
        Stopwatch one = Stopwatch.StartNew();
        bool escaped = false;
        string detail = "";
        try
        {
            VirePaths.CheckName(probe, 1);
            string combined = VirePaths.CombineUnder(root, probe, 1, 1);
            if (File.Exists(combined))
            {
                string text = VirePaths.ReadAllTextInside(combined, root, 1, 1);
                if (text != null && text.Contains("secret") && !InRoot(root, combined))
                    escaped = true;
            }
            try { VirePaths.DataOrSite(root, probe, 1); }
            catch (VireError) { }
            try { VirePaths.UseFile(root, probe, 1); }
            catch (VireError) { }
            try { VirePaths.ProgramFile(root, probe, 1); }
            catch (VireError) { }
        }
        catch (VireError err)
        {
            detail = err.Message;
            Assert.DoesNotContain("internal error", err.Message);
        }
        catch (Exception ex)
        {
            Note(stats, "path", probe, ex, one.ElapsedMilliseconds);
            return;
        }
        if (escaped)
        {
            stats.Crashes++;
            stats.Findings++;
            FuzzFinding finding = FuzzCore.SaveFinding(
                "path",
                "escape",
                "security",
                "Path bind or read returned bytes from outside the program folder.",
                probe,
                "outside=" + outside + " link=" + link);
            Log.Add(finding);
        }
        if (one.ElapsedMilliseconds > FuzzCore.HangMs)
            NoteHang(stats, "path", probe, one.ElapsedMilliseconds);
        if (rng.Next(20) == 0)
            JunctionOrDotDot(rng, stats, root, outside);
        _ = detail;
    }

    static void JunctionOrDotDot(FuzzRng rng, FuzzStats stats, string root, string outside)
    {
        string[] attacks =
        {
            "data/../" + Path.GetFileName(outside),
            "../" + Path.GetFileName(outside),
            "data/./../../" + Path.GetFileName(outside),
            "data/link.txt",
            "data\\..\\..\\" + Path.GetFileName(outside),
            "site/../data/ok.txt"
        };
        string probe = attacks[rng.Next(attacks.Length)];
        try
        {
            VirePaths.CheckName(probe, 1);
            string full = VirePaths.CombineUnder(root, probe, 1, 1);
            if (!InRoot(root, full))
            {
                stats.Crashes++;
                Log.Add(FuzzCore.SaveFinding(
                    "path",
                    "dotdot",
                    "security",
                    "CombineUnder resolved a path outside the sandbox.",
                    probe,
                    full));
            }
        }
        catch (VireError)
        {
        }
        catch (Exception ex)
        {
            Note(stats, "path", probe, ex, 0);
        }
    }

    static bool InRoot(string root, string full)
    {
        string a = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, '/') + Path.DirectorySeparatorChar;
        string b = Path.GetFullPath(full);
        return b.StartsWith(a, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)
            || string.Equals(Path.GetFullPath(root), b, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
    }

    static string MutatePath(FuzzRng rng, string probe)
    {
        return FuzzCore.MutateText(rng, probe).Replace('\n', '/');
    }

    static void ProbeBuiltinDirect(FuzzRng rng)
    {
        Dictionary<string, Func> funcs = new Dictionary<string, Func>();
        Func main = new Func();
        main.Body.Add("main");
        funcs["main"] = main;
        string folder = Path.Combine(Path.GetTempPath(), "vire-fuzz-bi");
        Directory.CreateDirectory(Path.Combine(folder, "data"));
        Machine machine = new Machine(funcs, folder);
        machine.budget.ApplyStepLimit(100000);
        string name = PickBuiltin(rng);
        List<object> args = BuiltinArgs(rng, name);
        try
        {
            machine.Call(name, args, 1);
        }
        catch (VireError)
        {
        }
    }

    static string PickBuiltin(FuzzRng rng)
    {
        string[] names =
        {
            "split", "join", "text", "has", "json", "parse", "push", "slice",
            "length", "lower", "upper", "replace", "find", "kind", "keys"
        };
        return names[rng.Next(names.Length)];
    }

    static List<object> BuiltinArgs(FuzzRng rng, string name)
    {
        List<object> args = new List<object>();
        if (name == "split")
        {
            args.Add(rng.Next(3) == 0 ? (object)new string('a', rng.Next(200)) : "a,b,c");
            args.Add(rng.Next(2) == 0 ? "," : "");
        }
        else if (name == "push")
        {
            List<object> list = new List<object>();
            int n = rng.Next(8);
            for (int i = 0; i < n; i++) list.Add(i);
            args.Add(list);
            args.Add(rng.Next(2) == 0 ? (object)rng.Next(9) : "x");
        }
        else if (name == "has")
        {
            Dictionary<string, object> map = new Dictionary<string, object>();
            map["k"] = 1;
            args.Add(rng.Next(4) == 0 ? (object)map : (object)"abc");
            args.Add("k");
        }
        else if (name == "parse" || name == "json")
        {
            args.Add(FuzzCore.JsonSnippet(rng));
        }
        else if (name == "join")
        {
            args.Add(new List<object> { "a", "b", rng.Next(4) == 0 ? (object)new List<object>() : "c" });
            args.Add(",");
        }
        else
        {
            args.Add("hello");
            if (rng.Next(2) == 0) args.Add(rng.Next(4));
            if (rng.Next(3) == 0) args.Add("x");
        }
        return args;
    }

    static string BuiltinProgram(FuzzRng rng)
    {
        StringBuilder text = new StringBuilder();
        text.Append("define main\n");
        text.Append("  try\n");
        text.Append("    say " + FuzzCore.BuiltinExpr(rng) + "\n");
        text.Append("    let xs be []\n");
        int n = rng.Next(20);
        text.Append("    let i be 0\n");
        text.Append("    while i < " + n + "\n");
        text.Append("      let xs be push with xs, i\n");
        text.Append("      let i be i + 1\n");
        text.Append("    end\n");
        text.Append("    say (xs at " + rng.Next(Math.Max(1, n)) + ")\n");
        text.Append("    say (\"abc\" at " + (rng.Next(6) - 2) + ")\n");
        text.Append("    say (\"ab\" + \"cd\" + \"ef\")\n");
        text.Append("    say (text with xs)\n");
        text.Append("    say (has with {\"a\":1}, \"a\")\n");
        text.Append("    parse with " + "\"" + FuzzCore.JsonSnippet(rng).Replace("\"", "\\\"") + "\"\n");
        text.Append("  miss problem\n");
        text.Append("    say problem\n");
        text.Append("  end\n");
        text.Append("end\n");
        return text.ToString();
    }

    static string GcProgram(FuzzRng rng)
    {
        int kind = rng.Next(5);
        if (kind == 0)
        {
            int bound = rng.Next(12) == 0 ? 100001 : 400;
            string done = bound > 100000 ? "escaped-list-cap" : "list-ok";
            return string.Join("\n", new string[]
            {
                "define main",
                "  let xs be []",
                "  let i be 0",
                "  try",
                "    while i < " + bound,
                "      let xs be push with xs, 1",
                "      let i be i + 1",
                "    end",
                "    say \"" + done + "\"",
                "  miss problem",
                "    say problem",
                "  end",
                "end",
                ""
            });
        }
        if (kind == 1)
        {
            return string.Join("\n", new string[]
            {
                "define main",
                "  let t be \"x\"",
                "  let i be 0",
                "  try",
                "    while i < 22",
                "      let t be t + t",
                "      let i be i + 1",
                "    end",
                "    say (length with t)",
                "  miss problem",
                "    say problem",
                "  end",
                "end",
                ""
            });
        }
        if (kind == 2)
        {
            return string.Join("\n", new string[]
            {
                "define main",
                "  let xs be []",
                "  let i be 0",
                "  while i < 200",
                "    let xs be push with xs, i",
                "    let i be i + 1",
                "  end",
                "  try",
                "    say (json with xs)",
                "    say (text with xs)",
                "    say (has with xs, 3)",
                "  miss problem",
                "    say problem",
                "  end",
                "end",
                ""
            });
        }
        if (kind == 3)
        {
            return string.Join("\n", new string[]
            {
                "define main",
                "  let t be \"abcdefghij\"",
                "  let i be 0",
                "  while i < 8",
                "    let t be t + t",
                "    let i be i + 1",
                "  end",
                "  say (t at 0)",
                "  say (split with t, \"cd\")",
                "  say (t + \"Z\")",
                "end",
                ""
            });
        }
        return string.Join("\n", new string[]
        {
            "define main",
            "  let m be {}",
            "  try",
            "    put 1 into m at \"k\"",
            "    say (has with m, \"k\")",
            "    say (m at \"k\")",
            "    say (text with m)",
            "  miss problem",
            "    say problem",
            "  end",
            "end",
            ""
        });
    }

    static int RunGuest(string source, int budget)
    {
        string captured;
        return RunGuest(source, budget, out captured);
    }

    static int RunGuest(string source, int budget, out string captured)
    {
        captured = "";
        string root = Path.Combine(Path.GetTempPath(), "vire-fuzz-guest-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(Path.Combine(root, "data"));
        string file = Path.Combine(root, "prog.vire");
        File.WriteAllText(file, source);
        TextWriter oldOut = Console.Out;
        TextWriter oldErr = Console.Error;
        TextReader oldIn = Console.In;
        StringWriter sink = new StringWriter();
        try
        {
            Console.SetOut(sink);
            Console.SetError(sink);
            Console.SetIn(TextReader.Null);
            Budget cap = new Budget();
            cap.ApplyStepLimit(budget);
            Program.RunFile(file, root, cap);
            captured = sink.ToString();
            if (captured.IndexOf("escaped-list-cap", StringComparison.Ordinal) >= 0)
                throw new InvalidOperationException("list cap 100000 was exceeded without fail-closed");
            if (captured.IndexOf("internal error", StringComparison.OrdinalIgnoreCase) >= 0)
                throw new InvalidOperationException("internal error printed");
            return 0;
        }
        catch (HaltSignal halt)
        {
            captured = sink.ToString();
            return halt.Code;
        }
        catch (VireError)
        {
            captured = sink.ToString();
            return 1;
        }
        finally
        {
            Console.SetOut(oldOut);
            Console.SetError(oldErr);
            Console.SetIn(oldIn);
            try { Directory.Delete(root, true); } catch (IOException) { }
        }
    }

    static void Note(FuzzStats stats, string target, string source, Exception ex, long ms)
    {
        if (FuzzCore.IsExpectedGuest(ex)) return;
        stats.Crashes++;
        stats.Findings++;
        string kind = ex.GetType().Name;
        string classification = FuzzCore.Classify(ex, target);
        string minimized = FuzzCore.MinimizeText(source, candidate =>
        {
            try
            {
                if (target == "frontend")
                {
                    new Parser(Lexer.Tokenize(candidate)).Parse();
                    return false;
                }
                RunGuest(candidate, 20000);
                return false;
            }
            catch (Exception replay)
            {
                return replay.GetType() == ex.GetType();
            }
        });
        FuzzFinding finding = FuzzCore.SaveFinding(
            target,
            kind,
            classification,
            "Host threw " + kind + " instead of a VireError/fail-closed stop. elapsed_ms=" + ms,
            minimized,
            ex.ToString());
        Log.Add(finding);
        if (Environment.GetEnvironmentVariable("VIRE_FUZZ_FAIL_ON_FINDING") == "1")
            throw new Xunit.Sdk.XunitException(classification + " " + finding.Path + " " + ex.Message);
    }

    static void NoteHang(FuzzStats stats, string target, string source, long ms)
    {
        stats.Hangs++;
        stats.Findings++;
        FuzzFinding finding = FuzzCore.SaveFinding(
            target,
            "hang",
            "robustness",
            "Iteration exceeded " + FuzzCore.HangMs + " ms (budget should fail closed before a hang).",
            source.Length > 2000 ? source.Substring(0, 2000) : source,
            "elapsed_ms=" + ms);
        Log.Add(finding);
    }
}
