using System;
using System.IO;
using System.Text;
using Xunit;

public class LockfileTests
{
    [Fact]
    public void ParserAcceptsCanonicalLockAndRefusesMalformed()
    {
        string hash = new string('a', 64);
        VireLockFile ok = VireLock.ParseText("vire.lock 1\npkg ui 0 packages/ui " + hash + "\n");
        Assert.Single(ok.Packages);
        Assert.Equal("ui", ok.Packages[0].Name);
        Assert.Equal("packages/ui", ok.Packages[0].Path);

        Assert.Throws<VireError>(() => VireLock.ParseText(""));
        Assert.Throws<VireError>(() => VireLock.ParseText("pkg ui 0 packages/ui " + hash + "\n"));
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 1\npkg ui 0 packages/ui " + hash + "\r\n"));
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 1\npkg ui 0 ../ui " + hash + "\n"));
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 1\npkg ui 0 packages/ui " + new string('A', 64) + "\n"));
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 1\npkg ui 0 packages/ui abc\n"));
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 1\npkg CON 0 packages/CON " + hash + "\n"));
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 1\nnot-a-pkg\n"));
        Assert.Throws<VireError>(() => VireLock.Parse(new byte[] { 0xef, 0xbb, 0xbf, (byte)'v' }));
        Assert.Throws<VireError>(() => VireLock.Parse(new byte[] { (byte)'v', 0 }));
        VireError huge = Assert.Throws<VireError>(() => VireLock.Parse(new byte[VireLock.MaxLockBytes + 1]));
        Assert.Contains("too large", huge.Message);
        StringBuilder many = new StringBuilder("vire.lock 1\n");
        for (int i = 0; i < VireLock.MaxPackages + 1; i++)
            many.Append("pkg p").Append(i).Append(" 0 packages/p").Append(i).Append(' ').Append(hash).Append('\n');
        VireError packed = Assert.Throws<VireError>(() => VireLock.ParseText(many.ToString()));
        Assert.Contains("too many", packed.Message);
        string dup = "vire.lock 1\npkg ui 0 packages/ui " + hash + "\npkg ui 1 packages/ui " + hash + "\n";
        Assert.Contains("twice", Assert.Throws<VireError>(() => VireLock.ParseText(dup)).Message);
    }

    [Fact]
    public void PkgLockAndVerifyStayInTheProjectFolder()
    {
        string dir = Scratch();
        string previous = Directory.GetCurrentDirectory();
        try
        {
            Directory.CreateDirectory(Path.Combine(dir, "packages", "demo"));
            File.WriteAllText(Path.Combine(dir, "packages", "demo", "lib.vire"), "define demo\n  return 1\nend\n");
            Directory.SetCurrentDirectory(dir);
            Assert.Equal(0, Program.Execute(new string[] { "pkg", "lock" }));
            Assert.True(File.Exists(Path.Combine(dir, "vire.lock")));
            string text = File.ReadAllText(Path.Combine(dir, "vire.lock"));
            Assert.StartsWith("vire.lock 1\n", text);
            Assert.Contains("pkg demo 0 packages/demo ", text);
            Assert.DoesNotContain("..", text);
            Assert.Equal(0, Program.Execute(new string[] { "pkg", "verify" }));
            File.AppendAllText(Path.Combine(dir, "packages", "demo", "lib.vire"), "~ tamper\n");
            using (StringWriter err = new StringWriter())
            {
                TextWriter old = Console.Error;
                Console.SetError(err);
                int code = Program.Execute(new string[] { "pkg", "verify" });
                Console.SetError(old);
                Assert.Equal(1, code);
                Assert.Contains("does not match", err.ToString());
            }
        }
        finally
        {
            Directory.SetCurrentDirectory(previous);
            TryDelete(dir);
        }
    }

    [Fact]
    public void NeedWithoutLockfileIsRefused()
    {
        string dir = Scratch();
        try
        {
            Directory.CreateDirectory(Path.Combine(dir, "deps", "ui"));
            File.WriteAllText(Path.Combine(dir, "deps", "ui", "lib.vire"), "define hello\n  return 1\nend\n");
            File.WriteAllText(Path.Combine(dir, "app.vire"), "need \"ui\"\ndefine main\n  say hello\nend\n");
            int code = Program.Execute(new string[] { Path.Combine(dir, "app.vire") });
            Assert.Equal(1, code);
        }
        finally { TryDelete(dir); }
    }

    [Fact]
    public void NeedWithMatchingLockRunsAndUseOfLocalFilesDoesNotNeedALock()
    {
        string dir = Scratch();
        string previous = Directory.GetCurrentDirectory();
        try
        {
            Directory.CreateDirectory(Path.Combine(dir, "packages", "demo"));
            File.WriteAllText(Path.Combine(dir, "packages", "demo", "lib.vire"), "define hello\n  return \"ok\"\nend\n");
            File.WriteAllText(Path.Combine(dir, "helper.vire"), "define extra\n  return 2\nend\n");
            File.WriteAllText(Path.Combine(dir, "app.vire"), "need \"demo\"\nuse \"helper.vire\"\ndefine main\n  say hello\n  say extra\nend\n");
            Directory.SetCurrentDirectory(dir);
            Assert.Equal(0, Program.Execute(new string[] { "pkg", "lock" }));
            int code = Program.Execute(new string[] { Path.Combine(dir, "app.vire") });
            Assert.Equal(0, code);
        }
        finally
        {
            Directory.SetCurrentDirectory(previous);
            TryDelete(dir);
        }
    }

    [Fact]
    public void MissingMismatchedAndMalformedLockFailInBothModes()
    {
        Dual("need \"demo\"\ndefine main\n  say hello\nend\n", true, false, false, "vire.lock is required");
        Dual("need \"demo\"\ndefine main\n  say hello\nend\n", true, true, true, "does not match");
        Dual("need \"demo\"\ndefine main\n  say hello\nend\n", true, true, false, "vire.lock", true);
        Dual("need \"other\"\ndefine main\n  say hello\nend\n", true, true, false, "is not in vire.lock");
        Dual("use \"packages/demo/lib.vire\"\ndefine main\n  say hello\nend\n", true, true, true, "does not match");
        Dual("use \"helper.vire\"\ndefine main\n  say extra\nend\n", false, false, false, null);
    }

    static void Dual(string source, bool withPkg, bool withLock, bool tamper, string needle, bool malformed = false)
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "conformance", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        Directory.CreateDirectory(Path.Combine(work, "data"));
        File.WriteAllText(Path.Combine(work, "prog.vire"), source);
        File.WriteAllText(Path.Combine(work, "helper.vire"), "define extra\n  return 1\nend\n");
        if (withPkg)
        {
            Directory.CreateDirectory(Path.Combine(work, "packages", "demo"));
            File.WriteAllText(Path.Combine(work, "packages", "demo", "lib.vire"), "define hello\n  return \"ok\"\nend\n");
        }
        string previous = Directory.GetCurrentDirectory();
        try
        {
            if (withLock)
            {
                Directory.SetCurrentDirectory(work);
                Assert.Equal(0, Program.Execute(new string[] { "pkg", "lock" }));
                if (tamper)
                    File.AppendAllText(Path.Combine(work, "packages", "demo", "lib.vire"), "~ no\n");
                if (malformed)
                    File.WriteAllText(Path.Combine(work, "vire.lock"), "not a lockfile\n");
            }
            DualMode.Proc interp = DualMode.RunVire(root, new string[] { "prog.vire" }, work);
            string relDir = Path.Combine("data", "conformance", Path.GetFileName(work)).Replace('\\', '/');
            DualMode.Proc compile = DualMode.RunVire(root, new string[]
            {
                "compiler.vire",
                relDir + "/prog.vire",
                relDir + "/prog.vc"
            }, root);
            if (needle == null)
            {
                Assert.Equal(0, interp.Code);
                Assert.Equal(0, compile.Code);
                DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "run", relDir + "/prog.vc" }, root);
                Assert.Equal(0, compiled.Code);
                Assert.Equal(DualMode.Norm(interp.Out), DualMode.Norm(compiled.Out));
                return;
            }
            Assert.Equal(1, interp.Code);
            Assert.Contains(needle, interp.Err);
            Assert.Equal(1, compile.Code);
            string compileText = compile.Err + compile.Out;
            Assert.Contains(needle, compileText);
        }
        finally
        {
            Directory.SetCurrentDirectory(previous);
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static string Scratch()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-lock-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static void TryDelete(string dir)
    {
        try { Directory.Delete(dir, true); } catch (IOException) { }
    }
}
