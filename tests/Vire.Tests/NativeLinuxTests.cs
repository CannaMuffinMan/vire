using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Xunit;

public class NativeLinuxTests
{
    [Fact]
    public void CheckWorkflowHasPinnedNativeLinuxJob()
    {
        string yml = File.ReadAllText(Path.Combine(DualMode.FindRoot(), ".github", "workflows", "check.yml"));
        Assert.Contains("native-linux:", yml);
        Assert.Contains("runs-on: ubuntu-latest", yml);
        Assert.Contains("bash tools/native-linux-smoke.sh", yml);
        Assert.Contains("actions/checkout@11d5960a326750d5838078e36cf38b85af677262", yml);
        Assert.Contains("actions/setup-dotnet@67a3573c9a986a3f9c594539f4ab511d57bb3ce9", yml);
    }

    [Fact]
    public void LinuxSmokeScriptCoversHelloSafetyAndNativeFixtures()
    {
        string smoke = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "tools", "native-linux-smoke.sh"));
        Assert.Contains("compile-native.vire", smoke);
        Assert.Contains("linux", smoke);
        Assert.Contains("samples/hello.vire", smoke);
        Assert.Contains("tests/native", smoke);
        Assert.Contains("native-error:", smoke);
        Assert.Contains("native-compile-error:", smoke);
        Assert.Contains("native-ok:", smoke);
        Assert.Contains("\\x7fELF", smoke);
        Assert.Contains("dotnet exec", smoke);
    }

    [Fact]
    public void CompileNativeLinuxWritesElfMagic()
    {
        if (!OperatingSystem.IsLinux() || RuntimeInformation.ProcessArchitecture != Architecture.X64)
            return;
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-linux-magic-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            string src = Path.Combine(work, "hello.vire");
            File.WriteAllText(src, "define main\n  say \"hello from vire\"\nend\n");
            string hexRel = Rel(root, Path.Combine(work, "hello.hex"));
            DualMode.Proc compile = DualMode.RunVire(root, new string[] { "compile-native.vire", Rel(root, src), hexRel, "linux" }, root);
            Assert.Equal(0, compile.Code);
            string hex = File.ReadAllText(Path.Combine(work, "hello.hex")).Trim();
            Assert.StartsWith("7f454c46", hex, StringComparison.OrdinalIgnoreCase);
            Assert.False(hex.StartsWith("4d5a", StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void NativeLinuxElfMatchesInterpreterForHelloAndSafety()
    {
        if (!OperatingSystem.IsLinux() || RuntimeInformation.ProcessArchitecture != Architecture.X64)
            return;
        string root = DualMode.FindRoot();
        CheckOne(root, Path.Combine(root, "samples", "hello.vire"), 0, "hello from vire", true, false);
        CheckOne(root, Path.Combine(root, "tests", "native", "oob-list.vire"), 1, "index is outside the value", false, false);
        CheckOne(root, Path.Combine(root, "tests", "native", "deep-rec.vire"), 1, "definitions called too deeply", false, false);
        CheckOne(root, Path.Combine(root, "tests", "native", "heap-bump.vire"), 1, "ran out of memory", false, true);
        CheckOne(root, Path.Combine(root, "tests", "native", "add-overflow.vire"), 1, "that number overflowed", false, true);
    }

    [Fact]
    public void NativeLinuxElfMatchesInterpreterForEveryNativeFixture()
    {
        if (!OperatingSystem.IsLinux() || RuntimeInformation.ProcessArchitecture != Architecture.X64)
            return;
        string root = DualMode.FindRoot();
        string dir = Path.Combine(root, "tests", "native");
        string[] files = Directory.GetFiles(dir, "*.vire");
        Assert.True(files.Length >= 40, "expected native fixtures");
        foreach (string path in files)
        {
            string text = File.ReadAllText(path);
            if (text.Contains("~ native-compile-error:", StringComparison.Ordinal))
            {
                string work = Path.Combine(root, "data", "native-linux-ce-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(work);
                try
                {
                    string copy = Path.Combine(work, Path.GetFileName(path));
                    File.Copy(path, copy);
                    DualMode.Proc compile = DualMode.RunVire(root, new string[] { "compile-native.vire", Rel(root, copy), Rel(root, Path.Combine(work, "out.hex")), "linux" }, root);
                    Assert.NotEqual(0, compile.Code);
                    Assert.Contains(WantCompile(text), DualMode.Norm(compile.Out) + DualMode.Norm(compile.Err));
                }
                finally
                {
                    try { Directory.Delete(work, true); } catch (IOException) { }
                }
                continue;
            }
            bool interpOk = text.Contains("~ native-interp-ok", StringComparison.Ordinal);
            if (text.Contains("~ native-ok:", StringComparison.Ordinal))
                CheckOne(root, path, 0, WantOk(text), true, false);
            else
                CheckOne(root, path, 1, WantOf(text), false, interpOk);
        }
    }

    static void CheckOne(string root, string srcPath, int wantCode, string wantText, bool exact, bool interpMayDiffer)
    {
        DualMode.Proc interp = DualMode.RunVire(root, new string[] { Rel(root, srcPath) }, root);
        string work = Path.Combine(root, "data", "native-linux-run-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            string copy = Path.Combine(work, Path.GetFileName(srcPath));
            File.Copy(srcPath, copy);
            string hexPath = Path.Combine(work, "out.hex");
            DualMode.Proc compile = DualMode.RunVire(root, new string[] { "compile-native.vire", Rel(root, copy), Rel(root, hexPath), "linux" }, root);
            Assert.True(compile.Code == 0, Path.GetFileName(srcPath) + " compile\n" + compile.Out + compile.Err);
            string hex = File.ReadAllText(hexPath).Trim();
            Assert.StartsWith("7f454c46", hex, StringComparison.OrdinalIgnoreCase);
            byte[] bytes = new byte[hex.Length / 2];
            for (int i = 0; i < bytes.Length; i++)
                bytes[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            string exe = Path.Combine(work, "prog");
            File.WriteAllBytes(exe, bytes);
            Process chmod = Process.Start(new ProcessStartInfo
            {
                FileName = "chmod",
                Arguments = "+x \"" + exe + "\"",
                UseShellExecute = false
            });
            chmod.WaitForExit();
            ProcessStartInfo info = new ProcessStartInfo
            {
                FileName = exe,
                WorkingDirectory = work,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            Process run = Process.Start(info);
            string stdout = run.StandardOutput.ReadToEnd();
            string stderr = run.StandardError.ReadToEnd();
            Assert.True(run.WaitForExit(30000), Path.GetFileName(srcPath) + " timed out");
            string combined = DualMode.Norm(stdout) + DualMode.Norm(stderr);
            Assert.Equal(wantCode, run.ExitCode);
            if (exact)
            {
                Assert.Equal(wantText.Trim(), DualMode.Norm(stdout).Trim());
                Assert.Equal(wantCode, interp.Code);
                Assert.Equal(wantText.Trim(), DualMode.Norm(interp.Out).Trim());
            }
            else
            {
                Assert.Contains(wantText, combined);
                if (!interpMayDiffer)
                {
                    Assert.Equal(wantCode, interp.Code);
                    string interpText = DualMode.Norm(interp.Err) + DualMode.Norm(interp.Out);
                    Assert.Contains(wantText, interpText);
                }
            }
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
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

    static string WantCompile(string text)
    {
        const string mark = "~ native-compile-error: ";
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
}
