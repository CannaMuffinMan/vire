using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using Xunit;

public class AttackCorpusTests
{
    [Fact]
    public void CorpusHasAtLeastFortyPrograms()
    {
        List<Entry> entries = LoadEntries();
        Assert.True(entries.Count >= 40, "attack corpus needs at least 40 programs, have " + entries.Count);
        HashSet<string> classes = new HashSet<string>();
        foreach (Entry entry in entries) classes.Add(entry.Class);
        string[] need =
        {
            "sql-injection", "html-injection", "shell-injection", "path-traversal",
            "ssrf", "deserialization", "secret-leakage", "resource-exhaustion", "malformed-vc"
        };
        foreach (string cls in need)
            Assert.True(classes.Contains(cls), "missing class " + cls);
        int tagged = 0;
        foreach (Entry entry in entries) tagged += entry.CompileReject.Count;
        Assert.True(tagged > 0, "at least one program should be tagged compile_reject");
    }

    [Fact]
    public void EveryCorpusProgramFailsSafelyInBothModes()
    {
        string root = DualMode.FindRoot();
        List<Entry> entries = LoadEntries();
        StringBuilder report = new StringBuilder();
        int failed = 0;
        foreach (Entry entry in entries)
        {
            string err = RunOne(root, entry);
            if (err != null)
            {
                failed++;
                report.Append(entry.Rel).Append(": ").Append(err).Append('\n');
            }
        }
        Assert.True(failed == 0, failed + " corpus program(s) failed:\n" + report);
    }

    static string RunOne(string root, Entry entry)
    {
        string work = Path.Combine(root, "data", "corpus-run", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        Directory.CreateDirectory(Path.Combine(work, "data"));
        Directory.CreateDirectory(Path.Combine(work, "site"));
        string outside = work + "-outside.txt";
        File.WriteAllText(outside, "OUTSIDE-SECRET");
        try
        {
            string destName = Path.GetFileName(entry.File);
            string dest = Path.Combine(work, destName);
            File.Copy(entry.File, dest);
            string relDir = Path.Combine("data", "corpus-run", Path.GetFileName(work)).Replace('\\', '/');
            string relSrc = (relDir + "/" + destName).Replace('\\', '/');
            DualMode.Proc interp;
            DualMode.Proc compiled;
            if (entry.Kind == "vc")
            {
                interp = DualMode.RunVire(root, new string[] { "run", relSrc }, root, entry.Budget);
                compiled = DualMode.RunVire(root, new string[] { "run", relSrc }, root, entry.Budget);
            }
            else
            {
                interp = DualMode.RunVire(root, new string[] { destName }, work, entry.Budget);
                string relVc = (relDir + "/" + Path.ChangeExtension(destName, ".vc")).Replace('\\', '/');
                DualMode.Proc compile = DualMode.RunVire(root, new string[] { "compiler.vire", relSrc, relVc }, root, "5000000");
                if (compile.Code != 0)
                    compiled = compile;
                else
                    compiled = DualMode.RunVire(root, new string[] { "run", relVc }, root, entry.Budget);
            }
            string iFail = CheckProc("interpreter", entry, interp);
            if (iFail != null) return iFail;
            string cFail = CheckProc("compiled", entry, compiled);
            if (cFail != null) return cFail;
            if (interp.Code != compiled.Code)
                return "exit codes differ interp=" + interp.Code + " compiled=" + compiled.Code
                    + " i-err=" + interp.Err + " c-err=" + compiled.Err + " c-out=" + compiled.Out;
            if (File.ReadAllText(outside) != "OUTSIDE-SECRET")
                return "sandbox escape: outside sentinel changed";
            if (Directory.Exists(Path.Combine(root, "PWNED")))
                return "sandbox escape: PWNED directory";
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
            try { File.Delete(outside); } catch (IOException) { }
        }
        return null;
    }

    static string CheckProc(string mode, Entry entry, DualMode.Proc proc)
    {
        if (proc.Code == 3)
            return mode + " crashed (exit 3): " + proc.Err;
        if (proc.Code != entry.Exit)
            return mode + " exit " + proc.Code + " want " + entry.Exit + " err=" + proc.Err + " out=" + proc.Out;
        string err = DualMode.Norm(proc.Err);
        string output = DualMode.Norm(proc.Out);
        string both = err + "\n" + output;
        foreach (string needle in entry.StderrContains)
        {
            if (string.IsNullOrEmpty(needle)) continue;
            if (both.IndexOf(needle, StringComparison.Ordinal) < 0)
                return mode + " output missing '" + needle + "': " + both;
        }
        foreach (string needle in entry.StderrForbids)
        {
            if (err.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0)
                return mode + " stderr leaked '" + needle + "': " + err;
        }
        foreach (string needle in entry.StdoutContains)
        {
            if (output.IndexOf(needle, StringComparison.Ordinal) < 0)
                return mode + " stdout missing '" + needle + "': " + output;
        }
        foreach (string needle in entry.StdoutForbids)
        {
            if (output.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0)
                return mode + " stdout leaked '" + needle + "': " + output;
        }
        return null;
    }

    static List<Entry> LoadEntries()
    {
        string root = DualMode.FindRoot();
        string dir = Path.Combine(root, "tests", "corpus");
        List<Entry> entries = new List<Entry>();
        foreach (string expectPath in Directory.GetFiles(dir, "*.expect.json", SearchOption.AllDirectories))
        {
            using (JsonDocument doc = JsonDocument.Parse(File.ReadAllText(expectPath)))
            {
                JsonElement map = doc.RootElement;
                string basePath = expectPath.Substring(0, expectPath.Length - ".expect.json".Length);
                Assert.True(File.Exists(basePath), "missing corpus file for " + expectPath);
                entries.Add(new Entry
                {
                    File = basePath,
                    Rel = Path.GetRelativePath(dir, basePath).Replace('\\', '/'),
                    Class = map.GetProperty("class").GetString(),
                    Kind = map.TryGetProperty("kind", out JsonElement kind) ? kind.GetString() : "source",
                    Exit = map.TryGetProperty("exit", out JsonElement exit) ? exit.GetInt32() : 1,
                    Budget = map.TryGetProperty("budget", out JsonElement budget) ? budget.ToString() : null,
                    StderrContains = Texts(map, "stderr_contains"),
                    StderrForbids = Texts(map, "stderr_forbids"),
                    StdoutContains = Texts(map, "stdout_contains"),
                    StdoutForbids = Texts(map, "stdout_forbids"),
                    CompileReject = Texts(map, "compile_reject")
                });
            }
        }
        entries.Sort((a, b) => string.CompareOrdinal(a.Rel, b.Rel));
        return entries;
    }

    static List<string> Texts(JsonElement map, string key)
    {
        List<string> items = new List<string>();
        JsonElement raw;
        if (!map.TryGetProperty(key, out raw) || raw.ValueKind != JsonValueKind.Array) return items;
        foreach (JsonElement item in raw.EnumerateArray())
            if (item.ValueKind == JsonValueKind.String) items.Add(item.GetString());
        return items;
    }

    sealed class Entry
    {
        public string File;
        public string Rel;
        public string Class;
        public string Kind;
        public int Exit;
        public string Budget;
        public List<string> StderrContains;
        public List<string> StderrForbids;
        public List<string> StdoutContains;
        public List<string> StdoutForbids;
        public List<string> CompileReject;
    }
}
