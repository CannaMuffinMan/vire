using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Xunit;

public class ConformanceTests
{
    static string TestKeyB64()
    {
        byte[] key = new byte[32];
        for (int i = 0; i < key.Length; i++) key[i] = (byte)(i + 3);
        return Convert.ToBase64String(key);
    }

    [Fact]
    public void GrammarProgramsMatchInBothModes()
    {
        string root = FindRoot();
        string[] names = { "else-if.vire", "for-skip.vire", "try-miss.vire", "map-decimal.vire", "use_main.vire" };
        foreach (string name in names)
        {
            string source = Path.Combine(root, "tests", "conformance", name);
            RunResult both = CompileAndCompare(root, source, ExtraFor(root, name));
            Assert.True(both.Matched, name + " interpreter vs compiled differed\n--- stdout i ---\n" + both.InterpOut + "\n--- stdout c ---\n" + both.CompOut + "\n--- stderr i ---\n" + both.InterpErr + "\n--- stderr c ---\n" + both.CompErr);
            Assert.Equal(0, both.InterpCode);
            Assert.Equal(0, both.CompCode);
        }
    }

    [Fact]
    public void CompiledDivisionErrorUsesRealLineAndColumn()
    {
        string root = FindRoot();
        string source = Path.Combine(root, "tests", "conformance", "boom.vire");
        RunResult both = CompileAndCompare(root, source, null);
        Assert.True(both.Matched, "boom outputs should match");
        Assert.Equal(1, both.InterpCode);
        Assert.Contains("division by zero", both.CompErr);
        Assert.Contains("line 4", both.CompErr);
        Assert.DoesNotContain("line 1:", both.CompErr);
        Match col = Regex.Match(both.CompErr, @"line 4 col (\d+)");
        Assert.True(col.Success, "compiled error should include a column on line 4: " + both.CompErr);
        Assert.True(int.Parse(col.Groups[1].Value) > 1, "compiled column should not be the dummy 1: " + both.CompErr);
    }

    [Fact]
    public void SuiteProgramsMatchInBothModes()
    {
        string root = FindRoot();
        List<string> programs = new List<string>();
        programs.Add(Path.Combine(root, "tests.vire"));
        AddMains(programs, Path.Combine(root, "checks"));
        AddMains(programs, Path.Combine(root, "systems"));
        StringBuilder report = new StringBuilder();
        int matched = 0;
        foreach (string program in programs)
        {
            string[] extra = null;
            if (Path.GetFileName(program).Equals("tests.vire", StringComparison.OrdinalIgnoreCase))
            {
                extra = new string[] { Path.Combine(root, "checks"), Path.Combine(root, "systems") };
            }
            RunResult both = CompileAndCompare(root, program, extra);
            if (both.Matched) matched++;
            else
            {
                report.AppendLine(program);
                report.AppendLine(" interp code " + both.InterpCode + " compiled code " + both.CompCode);
                report.AppendLine(" stdout i: " + both.InterpOut);
                report.AppendLine(" stdout c: " + both.CompOut);
                report.AppendLine(" stderr i: " + both.InterpErr);
                report.AppendLine(" stderr c: " + both.CompErr);
            }
        }
        Assert.True(programs.Count > 0);
        Assert.True(matched == programs.Count, "conformance mismatches (" + matched + "/" + programs.Count + "):\n" + report);
    }

    static string[] ExtraFor(string root, string name)
    {
        if (name == "use_main.vire")
            return new string[] { Path.Combine(root, "tests", "conformance", "use_lib.vire") };
        return null;
    }

    static void AddMains(List<string> programs, string dir)
    {
        foreach (string path in Directory.GetFiles(dir, "*.vire"))
        {
            string text = File.ReadAllText(path);
            if (text.Contains("define main")) programs.Add(path);
        }
    }

    static RunResult CompileAndCompare(string root, string source, string[] extra)
    {
        string work = Path.Combine(root, "data", "conformance", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            string destName = Path.GetFileName(source);
            string dest = Path.Combine(work, destName);
            File.Copy(source, dest, true);
            if (extra != null)
            {
                foreach (string item in extra)
                {
                    if (Directory.Exists(item))
                    {
                        string name = Path.GetFileName(item);
                        CopyTree(item, Path.Combine(work, name));
                    }
                    else if (File.Exists(item))
                        File.Copy(item, Path.Combine(work, Path.GetFileName(item)), true);
                }
            }
            RunResult interp = RunVire(root, new string[] { destName }, work);
            string relDir = Path.Combine("data", "conformance", Path.GetFileName(work));
            string relSrc = Path.Combine(relDir, destName).Replace('\\', '/');
            string relVc = Path.Combine(relDir, Path.ChangeExtension(destName, ".vc")).Replace('\\', '/');
            RunResult compile = RunVire(root, new string[] { "compiler.vire", relSrc, relVc }, root);
            if (compile.InterpCode != 0)
            {
                return new RunResult(false, interp.InterpCode, compile.InterpCode, interp.InterpOut, compile.InterpOut, interp.InterpErr, compile.InterpErr);
            }
            RunResult compiled = RunVire(root, new string[] { "run", relVc }, root);
            bool matched = interp.InterpCode == compiled.InterpCode
                && Norm(interp.InterpOut) == Norm(compiled.InterpOut)
                && NormErr(interp.InterpErr) == NormErr(compiled.InterpErr);
            return new RunResult(matched, interp.InterpCode, compiled.InterpCode, interp.InterpOut, compiled.InterpOut, interp.InterpErr, compiled.InterpErr);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static void CopyTree(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (string file in Directory.GetFiles(from))
            File.Copy(file, Path.Combine(to, Path.GetFileName(file)), true);
        foreach (string dir in Directory.GetDirectories(from))
            CopyTree(dir, Path.Combine(to, Path.GetFileName(dir)));
    }

    static string Norm(string text)
    {
        return (text ?? "").Replace("\r\n", "\n");
    }

    static string NormErr(string text)
    {
        return Regex.Replace(Norm(text), @"line (\d+) col \d+", "line $1");
    }

    static RunResult RunVire(string root, string[] args, string cwd)
    {
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        StringBuilder argv = new StringBuilder();
        argv.Append("exec \"").Append(dll).Append("\"");
        foreach (string arg in args)
            argv.Append(" \"").Append(arg).Append("\"");
        info.Arguments = argv.ToString();
        info.WorkingDirectory = cwd;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_SEAL_KEY"] = TestKeyB64();
        info.Environment["VIRE_BUDGET"] = "5000000";
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(120000), "conformance process timed out");
        return new RunResult(true, process.ExitCode, process.ExitCode, stdout, stdout, stderr, stderr);
    }

    static string FindRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "vire.csproj")) && File.Exists(Path.Combine(dir, "tests.vire")))
                return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root");
    }

    sealed class RunResult
    {
        public bool Matched;
        public int InterpCode;
        public int CompCode;
        public string InterpOut;
        public string CompOut;
        public string InterpErr;
        public string CompErr;

        public RunResult(bool matched, int interpCode, int compCode, string interpOut, string compOut, string interpErr, string compErr)
        {
            Matched = matched;
            InterpCode = interpCode;
            CompCode = compCode;
            InterpOut = interpOut;
            CompOut = compOut;
            InterpErr = interpErr;
            CompErr = compErr;
        }
    }
}
