using System;
using System.IO;
using Xunit;

public class DepsLockTests
{
    [Fact]
    public void MatchingLockLoadsThePackage()
    {
        string dir = TempDir();
        try
        {
            string lib = WritePackage(dir, "greet", "define greet\n  return \"hi\"\nend\n");
            WriteLock(dir, "greet", VireSeal.HashText(File.ReadAllText(lib)));
            WriteProgram(dir, "need \"greet\"\n\ndefine main\n  say greet\nend\n");
            RunResult run = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(0, run.Code);
            Assert.Contains("hi", run.Out);
            Assert.DoesNotContain("deps.lock", run.Err);
        }
        finally { TryDelete(dir); }
    }

    [Fact]
    public void HashMismatchRefusesThePackage()
    {
        string dir = TempDir();
        try
        {
            WritePackage(dir, "greet", "define greet\n  return \"hi\"\nend\n");
            WriteLock(dir, "greet", new string('a', 64));
            WriteProgram(dir, "need \"greet\"\n\ndefine main\n  say greet\nend\n");
            RunResult run = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(1, run.Code);
            Assert.Contains("deps.lock does not match greet", run.Err);
            Assert.DoesNotContain("hi", run.Out);
        }
        finally { TryDelete(dir); }
    }

    [Fact]
    public void MissingPackageRefusesTheLoad()
    {
        string dir = TempDir();
        try
        {
            WritePackage(dir, "greet", "define greet\n  return \"hi\"\nend\n");
            WriteLock(dir, "other", new string('b', 64));
            WriteProgram(dir, "need \"greet\"\n\ndefine main\n  say greet\nend\n");
            RunResult run = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(1, run.Code);
            Assert.Contains("deps.lock does not name greet", run.Err);
            Assert.DoesNotContain("hi", run.Out);
        }
        finally { TryDelete(dir); }
    }

    [Fact]
    public void LockHexEqualScansEveryCharacter()
    {
        string match = new string('a', 64);
        Assert.True(VirePaths.LockHexEqual(match, match));
        string first = "b" + new string('a', 63);
        string last = new string('a', 63) + "b";
        Assert.False(VirePaths.LockHexEqual(match, first));
        Assert.False(VirePaths.LockHexEqual(match, last));
        Assert.False(VirePaths.LockHexEqual(match, new string('a', 63)));
        Assert.False(VirePaths.LockHexEqual(null, match));
    }

    [Fact]
    public void LastHexNibbleMismatchRefusesThePackage()
    {
        string dir = TempDir();
        try
        {
            string lib = WritePackage(dir, "greet", "define greet\n  return \"hi\"\nend\n");
            string hex = VireSeal.HashText(File.ReadAllText(lib));
            char flip = hex[63] == 'a' ? 'b' : 'a';
            WriteLock(dir, "greet", hex.Substring(0, 63) + flip);
            WriteProgram(dir, "need \"greet\"\n\ndefine main\n  say greet\nend\n");
            RunResult run = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(1, run.Code);
            Assert.Contains("deps.lock does not match greet", run.Err);
            Assert.DoesNotContain("hi", run.Out);
        }
        finally { TryDelete(dir); }
    }

    [Fact]
    public void ProgramCannotWriteLockPackageOrVireNames()
    {
        string[] blocked =
        {
            "deps.lock",
            "DEPS.LOCK",
            "deps.lock.",
            "deps.lock ",
            "deps.lock:stream",
            "deps.lock::$DATA",
            "lib.vire",
            "lib.vire.",
            "lib.vire::$DATA",
            "foo.vire:stream",
            "foo.vire::$DATA",
            "note.txt:evil.vire",
            "note.txt:deps.lock",
            "site/deps.lock",
            "data/pkg/lib.vire"
        };
        for (int i = 0; i < blocked.Length; i++)
        {
            VireError err = Assert.Throws<VireError>(() => VirePaths.RefuseProgram(blocked[i], 1));
            Assert.Contains("will not write a program file", err.Message);
        }
        VirePaths.RefuseProgram("data/note.txt", 1);
        VirePaths.RefuseProgram("site/app.js", 1);

        string dir = TempDir();
        try
        {
            Directory.CreateDirectory(Path.Combine(dir, "data"));
            File.WriteAllText(Path.Combine(dir, "data", "note.txt"), "seed");
            string[] writes =
            {
                "data/deps.lock",
                "data/DEPS.LOCK",
                "data/nested/deps.lock",
                "data/lib.vire",
                "data/pkg/lib.vire",
                "data/evil.vire"
            };
            for (int i = 0; i < writes.Length; i++)
            {
                string rel = writes[i];
                WriteProgram(dir, "can fs.write data\ndefine main\n  write with \"" + rel + "\", \"pwn\"\nend\n");
                RunResult run = Run(Path.Combine(dir, "main.vire"));
                Assert.Equal(1, run.Code);
                Assert.Contains("will not write a program file", run.Err);
            }
            string[] tricky =
            {
                "data/evil.vire.",
                "data/deps.lock.",
                "data/note.txt:evil.vire",
                "data/deps.lock::$DATA",
                "data/foo.vire:stream"
            };
            for (int i = 0; i < tricky.Length; i++)
            {
                string rel = tricky[i];
                WriteProgram(dir, "can fs.write data\ndefine main\n  write with \"" + rel + "\", \"pwn\"\nend\n");
                RunResult run = Run(Path.Combine(dir, "main.vire"));
                Assert.Equal(1, run.Code);
                Assert.DoesNotContain("pwn", run.Out);
            }
            WriteProgram(dir, "can fs.write data\ndefine main\n  copy with \"data/note.txt\", \"data/deps.lock\"\nend\n");
            RunResult copied = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(1, copied.Code);
            Assert.Contains("will not write a program file", copied.Err);
            File.WriteAllText(Path.Combine(dir, "data", "deps.lock"), "kept\n");
            WriteProgram(dir, "can fs.write data\ndefine main\n  append with \"data/deps.lock\", \"pwn\"\nend\n");
            RunResult appended = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(1, appended.Code);
            Assert.Equal("kept\n", File.ReadAllText(Path.Combine(dir, "data", "deps.lock")));
            Assert.False(File.Exists(Path.Combine(dir, "data", "lib.vire")));
            Assert.False(File.Exists(Path.Combine(dir, "data", "evil.vire")));
        }
        finally { TryDelete(dir); }
    }

    [Fact]
    public void NeedRefusesReparseLockAndPackage()
    {
        string dir = TempDir();
        string outside = Path.Combine(Path.GetTempPath(), "vire-lock-out-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(outside);
        try
        {
            string body = "define greet\n  return \"hi\"\nend\n";
            string lib = WritePackage(dir, "greet", body);
            string hex = VireSeal.HashText(File.ReadAllText(lib));
            string realLock = Path.Combine(outside, "deps.lock");
            File.WriteAllText(realLock, "greet " + hex + "\n");
            string lockPath = Path.Combine(dir, "deps.lock");
            try { File.CreateSymbolicLink(lockPath, realLock); }
            catch (Exception ex)
            {
                Console.WriteLine("symlink test skipped: " + ex.GetType().Name);
                return;
            }
            WriteProgram(dir, "need \"greet\"\n\ndefine main\n  say greet\nend\n");
            RunResult lockRun = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(1, lockRun.Code);
            Assert.Contains("program folder", lockRun.Err);
            Assert.DoesNotContain("hi", lockRun.Out);

            File.Delete(lockPath);
            WriteLock(dir, "greet", hex);
            string realLib = Path.Combine(outside, "lib.vire");
            File.WriteAllText(realLib, body);
            File.Delete(lib);
            try { File.CreateSymbolicLink(lib, realLib); }
            catch (Exception ex)
            {
                Console.WriteLine("symlink test skipped: " + ex.GetType().Name);
                return;
            }
            RunResult libRun = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(1, libRun.Code);
            Assert.Contains("program folder", libRun.Err);
            Assert.DoesNotContain("hi", libRun.Out);
        }
        finally
        {
            TryDelete(dir);
            TryDelete(outside);
        }
    }

    [Fact]
    public void CompilersHashAndParseTheSamePackageBytes()
    {
        string compiler = File.ReadAllText(Path.Combine(RepoRoot(), "compiler.vire"));
        string native = File.ReadAllText(Path.Combine(RepoRoot(), "compile-native.vire"));
        Assert.Contains("sameHex with (hash with body), locked", compiler);
        Assert.Contains("put body into state at \"forced\"", compiler);
        Assert.Contains("let extra be compileUnit with next, seen, state", compiler);
        Assert.DoesNotContain("(hash with body) ==", compiler);
        Assert.Contains("let pinned be body", native);
        Assert.Contains("sameHex with (hash with pinned)", native);
        Assert.Contains("loadText with next, pinned, folder, seen", native);
        Assert.DoesNotContain("(hash with body) ==", native);
    }

    [Fact]
    public void ProgramWithNoNeedRunsWithoutALock()
    {
        string dir = TempDir();
        try
        {
            WriteProgram(dir, "define main\n  say \"plain\"\nend\n");
            Assert.False(File.Exists(Path.Combine(dir, "deps.lock")));
            RunResult run = Run(Path.Combine(dir, "main.vire"));
            Assert.Equal(0, run.Code);
            Assert.Contains("plain", run.Out);
        }
        finally { TryDelete(dir); }
    }

    static string WritePackage(string dir, string name, string body)
    {
        string folder = Path.Combine(dir, "deps", name);
        Directory.CreateDirectory(folder);
        string path = Path.Combine(folder, "lib.vire");
        File.WriteAllText(path, body);
        return path;
    }

    static void WriteLock(string dir, string name, string hex)
    {
        File.WriteAllText(Path.Combine(dir, "deps.lock"), name + " " + hex + "\n");
    }

    static void WriteProgram(string dir, string body)
    {
        File.WriteAllText(Path.Combine(dir, "main.vire"), body);
    }

    static string RepoRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8 && !string.IsNullOrEmpty(dir); i++)
        {
            if (File.Exists(Path.Combine(dir, "compiler.vire")) && File.Exists(Path.Combine(dir, "Vire.cs")))
                return dir;
            dir = Path.GetDirectoryName(dir);
        }
        return Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
    }

    static string TempDir()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-deps-lock-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static void TryDelete(string dir)
    {
        try { Directory.Delete(dir, true); } catch (IOException) { }
    }

    static RunResult Run(string program)
    {
        TextWriter previousOut = Console.Out;
        TextWriter previousErr = Console.Error;
        StringWriter stdout = new StringWriter();
        StringWriter stderr = new StringWriter();
        Console.SetOut(stdout);
        Console.SetError(stderr);
        try
        {
            int code = Program.Execute(new string[] { program });
            return new RunResult(code, stdout.ToString(), stderr.ToString());
        }
        finally
        {
            Console.SetOut(previousOut);
            Console.SetError(previousErr);
        }
    }

    sealed class RunResult
    {
        public int Code;
        public string Out;
        public string Err;
        public RunResult(int code, string stdout, string stderr)
        {
            Code = code;
            Out = stdout;
            Err = stderr;
        }
    }
}
