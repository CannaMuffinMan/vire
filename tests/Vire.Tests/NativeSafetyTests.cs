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
        string rtCore = File.ReadAllText(Path.Combine(root, "src", "rt.vire"));
        string compiler = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.Contains("72, 131, 228, 240", rtCore);
        Assert.Contains("rt_enter", rt);
        Assert.Contains("rt_leave", rt);
        Assert.Contains("call_depth", rt);
        Assert.Contains("definitions called too deeply", rt);
        Assert.Contains("ran out of memory", rt);
        Assert.Contains("that number overflowed", rt);
        Assert.Contains("list is too large", rt);
        Assert.Contains("emitFit32", rt);
        Assert.Contains("1048576", rt);
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
        Assert.True(files.Length >= 28, "expected native safety fixtures");
        foreach (string path in files)
        {
            string text = File.ReadAllText(path);
            DualMode.Proc run = DualMode.RunVire(root, new string[] { Rel(root, path) }, root);
            if (text.Contains("~ native-ok:"))
            {
                Assert.Equal(0, run.Code);
                string ok = WantOk(text);
                Assert.False(string.IsNullOrEmpty(ok), path);
                Assert.Contains(ok, DualMode.Norm(run.Out));
                continue;
            }
            if (text.Contains("~ native-interp-ok"))
            {
                Assert.Equal(0, run.Code);
                Assert.DoesNotContain("internal error", DualMode.Norm(run.Err));
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
            Assert.Contains(AsciiHex("ran out of memory"), hex);
            Assert.Contains(AsciiHex("that number overflowed"), hex);
            Assert.Contains(AsciiHex("division by zero"), hex);
            Assert.Contains(AsciiHex("list is too large"), hex);
            Assert.Contains(AsciiHex("text is too large to write"), hex);
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

    [Fact]
    public void NumberWithTextMatchesInterpreterAndCompiled()
    {
        string root = DualMode.FindRoot();
        string dir = Path.Combine(root, "tests", "native");
        string[] names = {
            "num-max.vire", "num-ovf-pos.vire", "num-ovf-neg.vire", "num-min.vire",
            "num-i64-max.vire", "num-i64-min.vire", "num-past-i64.vire", "num-huge.vire",
            "num-junk-lead.vire", "num-junk-trail.vire", "num-junk-ovf-trail.vire", "num-empty.vire"
        };
        Assert.Equal(12, names.Length);
        foreach (string name in names)
        {
            string path = Path.Combine(dir, name);
            string text = File.ReadAllText(path);
            DualMode.DualRun both = DualMode.RunSource(text, null);
            Assert.True(both.Matched, name + " interpreter vs compiled differed\n stdout i=" + both.InterpOut + " c=" + both.CompOut + "\n stderr i=" + both.InterpErr + " c=" + both.CompErr);
            if (text.Contains("~ native-ok:") || text.Contains("~ native-interp-ok"))
            {
                Assert.Equal(0, both.InterpCode);
                Assert.DoesNotContain("internal error", DualMode.Norm(both.InterpErr));
                Assert.DoesNotContain("internal error", DualMode.Norm(both.CompErr));
                continue;
            }
            Assert.Equal(1, both.InterpCode);
            string want = WantOf(text);
            Assert.False(string.IsNullOrEmpty(want), name);
            Assert.Contains(want, DualMode.Norm(both.InterpErr) + DualMode.Norm(both.InterpOut));
            Assert.Contains(want, DualMode.Norm(both.CompErr) + DualMode.Norm(both.CompOut));
        }
        string rt = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        int start = rt.IndexOf("pin with labels, \"rt_number\"", StringComparison.Ordinal);
        int stop = rt.IndexOf("pin with labels, \"rt_length\"", StringComparison.Ordinal);
        Assert.True(start >= 0 && stop > start, "rt_number block");
        string body = rt.Substring(start, stop - start);
        Assert.Contains("emitFit32", body);
        Assert.Contains("num_ovf", body);
        Assert.DoesNotContain("emitJcc with image, fixes, 128, \"num_ovf\"", body);
    }

    [Fact]
    public void ListCatAndTextCatShareInterpreterCaps()
    {
        string root = DualMode.FindRoot();
        DualMode.DualRun lists = DualMode.RunSource(
            "define main\n  let a be span with 0, 50001\n  let b be span with 0, 50001\n  say a + b\nend\n",
            null);
        Assert.True(lists.Matched, "interp=" + lists.InterpErr + " compiled=" + lists.CompErr);
        Assert.Equal(1, lists.InterpCode);
        Assert.Contains("list is too large", DualMode.Norm(lists.InterpErr));
        Assert.Contains("list is too large", DualMode.Norm(lists.CompErr));
        DualMode.DualRun texts = DualMode.RunSource(
            "define main\n  let a be \"\"\n  let n be 0\n  while n < 20\n    let a be a + a + \"x\"\n    let n be n + 1\n  end\n  say a + a\nend\n",
            null);
        Assert.True(texts.Matched, "interp=" + texts.InterpErr + " compiled=" + texts.CompErr);
        Assert.Equal(1, texts.InterpCode);
        Assert.Contains("text is too large to write", DualMode.Norm(texts.InterpErr));
        string rt = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        int cat = rt.IndexOf("rt_list_cat", StringComparison.Ordinal);
        int cap = rt.IndexOf("100000", cat, StringComparison.Ordinal);
        int alloc = rt.IndexOf("rt_alloc", cat, StringComparison.Ordinal);
        Assert.True(cap > cat && cap < alloc, "rt_list_cat must check 100000 before rt_alloc");
        int tcat = rt.IndexOf("rt_text_cat", StringComparison.Ordinal);
        int tcap = rt.IndexOf("1000000", tcat, StringComparison.Ordinal);
        int talloc = rt.IndexOf("rt_alloc", tcat, StringComparison.Ordinal);
        Assert.True(tcap > tcat && tcap < talloc, "rt_text_cat must check 1000000 before rt_alloc");
    }

    static string WantOk(string text)
    {
        const string mark = "~ native-ok: ";
        int at = text.IndexOf(mark, StringComparison.Ordinal);
        if (at < 0) return "";
        int end = text.IndexOf('\n', at);
        if (end < 0) end = text.Length;
        return text.Substring(at + mark.Length, end - (at + mark.Length)).Trim();
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
