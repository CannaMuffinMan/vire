using System;
using System.IO;
using System.Text;
using Xunit;

public class NativeSafetyTests
{
    [Fact]
    public void NativeRuntimeCountsCallsAndGuardsTheStack()
    {
        string root = DualMode.FindRoot();
        string rt = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        string compiler = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.Contains("rt_enter", rt);
        Assert.Contains("rt_leave", rt);
        Assert.Contains("call_depth", rt);
        Assert.Contains("definitions called too deeply", rt);
        Assert.Contains("index is outside the value", rt);
        Assert.Contains("an index must be a whole number", rt);
        Assert.Contains("[101, 72, 139, 4, 37, 16, 0, 0, 0, 72, 57, 196]", rt);
        Assert.DoesNotContain("16384", rt);
        Assert.Contains("emitCall with gen, \"rt_enter\"", compiler);
        Assert.Contains("emitCall with gen, \"rt_leave\"", compiler);
        Assert.Contains("emitCall with gen, \"rt_at\"", compiler);
        Assert.Contains("rt_set_slot", compiler);
    }

    [Fact]
    public void NativeFixturesMatchInterpreterErrors()
    {
        string root = DualMode.FindRoot();
        string dir = Path.Combine(root, "tests", "native");
        string[] files = Directory.GetFiles(dir, "*.vire");
        Assert.True(files.Length >= 10, "expected native safety fixtures");
        foreach (string path in files)
        {
            string text = File.ReadAllText(path);
            DualMode.Proc run = DualMode.RunVire(root, new string[] { Rel(root, path) }, root);
            if (text.Contains("~ native-ok:"))
            {
                Assert.Equal(0, run.Code);
                Assert.Contains("0", DualMode.Norm(run.Out));
                continue;
            }
            Assert.Equal(1, run.Code);
            string want = WantOf(text);
            Assert.False(string.IsNullOrEmpty(want), path);
            string err = DualMode.Norm(run.Err);
            string output = DualMode.Norm(run.Out);
            Assert.True(err.Contains(want) || output.Contains(want), Path.GetFileName(path) + " missing " + want + "\nstderr=" + err + "\nstdout=" + output);
            Assert.DoesNotContain("internal error", err);
        }
    }

    [Fact]
    public void NativeImageCarriesSafetyMessages()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-safety-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            string src = Path.Combine(work, "probe.vire");
            File.WriteAllText(src, "define main\n  say [1] at 0\nend\n");
            string hexRel = Rel(root, Path.Combine(work, "probe.hex"));
            string srcRel = Rel(root, src);
            DualMode.Proc compile = DualMode.RunVire(root, new string[] { "compile-native.vire", srcRel, hexRel }, root);
            Assert.Equal(0, compile.Code);
            string hex = File.ReadAllText(Path.Combine(work, "probe.hex"));
            Assert.Contains(AsciiHex("index is outside the value"), hex);
            Assert.Contains(AsciiHex("definitions called too deeply"), hex);
            Assert.Contains(AsciiHex("an index must be a whole number"), hex);
            Assert.Contains(AsciiHex("slice needs text or a list"), hex);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void NativeSmokeRunsEveryNativeFixture()
    {
        string root = DualMode.FindRoot();
        string smoke = File.ReadAllText(Path.Combine(root, "tools", "native-smoke.ps1"));
        Assert.Contains("tests/native", smoke);
        Assert.Contains("Get-ChildItem", smoke);
        Assert.Contains("~ native-error:", smoke);
        Assert.DoesNotContain("KNOWN FAIL Phase 3B", smoke);
    }

    static string WantOf(string text)
    {
        const string mark = "~ native-error: ";
        int at = text.IndexOf(mark, StringComparison.Ordinal);
        if (at < 0) return "";
        int end = text.IndexOf('\n', at);
        if (end < 0) end = text.Length;
        return text.Substring(at + mark.Length, end - (at + mark.Length)).Trim();
    }

    static string Rel(string root, string path)
    {
        return Path.GetRelativePath(root, path).Replace('\\', '/');
    }

    static string AsciiHex(string text)
    {
        StringBuilder hex = new StringBuilder();
        foreach (char ch in text)
        {
            hex.Append(((int)ch).ToString("x2"));
        }
        return hex.ToString();
    }
}
