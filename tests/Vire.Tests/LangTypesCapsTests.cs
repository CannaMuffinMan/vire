using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

public class LangTypesCapsTests
{
    static string Root() { return DualMode.FindRoot(); }

    static string LoadErr(string source)
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-lang-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "prog.vire");
            File.WriteAllText(path, source);
            VireError err = Assert.Throws<VireError>(() => Program.Load(path, dir, new HashSet<string>()));
            return err.Message;
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    static DualMode.Proc NativeCompile(string sourceText)
    {
        string root = Root();
        string work = Path.Combine(root, "data", "lang-guest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "prog.vire"), sourceText);
        string rel = ("data/" + Path.GetFileName(work) + "/prog.vire").Replace('\\', '/');
        string hex = ("data/" + Path.GetFileName(work) + "/prog.hex").Replace('\\', '/');
        return DualMode.RunVire(root, new string[] { "compile-native.vire", rel, hex }, root);
    }

    [Fact]
    public void UntypedProgramStillLoads()
    {
        string root = Root();
        string path = Path.Combine(root, "tests", "lang", "untyped.vire");
        Dictionary<string, Func> funcs = Program.Load(path, Path.GetDirectoryName(path), new HashSet<string>());
        Assert.True(funcs.ContainsKey("main"));
        DualMode.Proc native = NativeCompile(File.ReadAllText(path));
        Assert.Equal(0, native.Code);
        Assert.Contains("capabilities: none", DualMode.Norm(native.Out));
        Assert.Contains("compiled", DualMode.Norm(native.Out));
    }

    [Fact]
    public void TypedOkOnHostAndNative()
    {
        string root = Root();
        string path = Path.Combine(root, "tests", "lang", "typed-ok.vire");
        Dictionary<string, Func> funcs = Program.Load(path, Path.GetDirectoryName(path), new HashSet<string>());
        Assert.True(funcs.ContainsKey("add"));
        DualMode.Proc native = NativeCompile(File.ReadAllText(path));
        Assert.Equal(0, native.Code);
        Assert.Contains("compiled", DualMode.Norm(native.Out));
    }

    [Fact]
    public void TypeErrorMatchesHostAndNative()
    {
        string want = "n is number, got text";
        Assert.Equal(want, LoadErr(File.ReadAllText(Path.Combine(Root(), "tests", "lang", "typed-bad.vire"))));
        DualMode.Proc native = NativeCompile(File.ReadAllText(Path.Combine(Root(), "tests", "lang", "typed-bad.vire")));
        Assert.NotEqual(0, native.Code);
        Assert.Contains(want, DualMode.Norm(native.Out));
        Assert.Contains("compile failed", DualMode.Norm(native.Out));
    }

    [Fact]
    public void MissingCapabilityMatchesHostAndNative()
    {
        string want = "now needs capability clock";
        Assert.Equal(want, LoadErr(File.ReadAllText(Path.Combine(Root(), "tests", "lang", "cap-bad.vire"))));
        DualMode.Proc native = NativeCompile(File.ReadAllText(Path.Combine(Root(), "tests", "lang", "cap-bad.vire")));
        Assert.NotEqual(0, native.Code);
        Assert.Contains(want, DualMode.Norm(native.Out));
    }

    [Fact]
    public void DeclaredClockIsReported()
    {
        string path = Path.Combine(Root(), "tests", "lang", "cap-ok.vire");
        Program.Load(path, Path.GetDirectoryName(path), new HashSet<string>());
        DualMode.Proc native = NativeCompile(File.ReadAllText(path));
        Assert.Equal(0, native.Code);
        Assert.Contains("capabilities: clock", DualMode.Norm(native.Out));
    }

    [Fact]
    public void LanguageDocListsEveryHostBuiltin()
    {
        string doc = File.ReadAllText(Path.Combine(Root(), "docs", "LANGUAGE.md"));
        foreach (string name in Machine.BuiltinNames)
            Assert.Contains("`"+ name + "`", doc);
    }

    [Fact]
    public void UnknownTypeIsACompileError()
    {
        Assert.Equal("unknown type widget", LoadErr("define main\n  let n: widget be 1\nend\n"));
    }

    [Fact]
    public void ParamMismatchMatchesHostAndNative()
    {
        string src = "define f with a: number as number\n  return a\nend\ndefine main\n  say (f with \"x\")\nend\n";
        string want = "f takes number, got text";
        Assert.Equal(want, LoadErr(src));
        string root = Root();
        DualMode.Proc native = NativeCompile(src);
        Assert.NotEqual(0, native.Code);
        Assert.Contains(want, DualMode.Norm(native.Out));
    }
}
