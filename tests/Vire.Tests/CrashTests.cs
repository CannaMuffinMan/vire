using System;
using System.Diagnostics;
using System.IO;
using Xunit;

public class CrashTests
{
    [Fact]
    public void CrashFixturesStayAlive()
    {
        string root = RepoRoot();
        string crash = Path.Combine(root, "tests", "crash");

        RunResult cycle = Run(root, Path.Combine(crash, "cycle-say.vire"), null);
        Assert.Equal(0, cycle.Code);
        Assert.Contains("[...]", cycle.StdOut);

        RunResult json = Run(root, Path.Combine(crash, "cycle-json.vire"), null);
        Assert.Equal(1, json.Code);
        Assert.Contains("json can't write a list or map that contains itself", json.StdErr);

        string deepProgram = Path.Combine(crash, "deep-json.vire");
        File.WriteAllText(deepProgram, "define main\n  parse with \"" + new string('[', 100000) + new string(']', 100000) + "\"\n  say \"lived\"\nend\n");
        try
        {
            RunResult deep = Run(root, deepProgram, null);
            Assert.Equal(1, deep.Code);
            Assert.Contains("json is nested too deeply", deep.StdErr);
        }
        finally { File.Delete(deepProgram); }

        RunResult arith = Run(root, Path.Combine(crash, "arith.vire"), null);
        Assert.Equal(0, arith.Code);
        Assert.Equal("0\n2147483648\n2147483648\n2147483648\n", arith.StdOut.Replace("\r\n", "\n"));

        RunResult self = Run(root, Path.Combine(crash, "self-run.vire"), null);
        Assert.Equal(1, self.Code);
        Assert.Contains("run went too deep", self.StdErr);

        RunResult nested = Run(root, Path.Combine(crash, "nest-run.vire"), "50");
        Assert.Equal(1, nested.Code);
        Assert.Contains("program ran too long", nested.StdErr);
        Assert.DoesNotContain("parent", nested.StdOut);

        string wide = Path.Combine(crash, "wide-expr.vire");
        File.WriteAllText(wide, "define main\n  say " + new string('(', 200) + "1" + new string(')', 200) + "\nend\n");
        string tooWide = Path.Combine(crash, "too-wide-expr.vire");
        File.WriteAllText(tooWide, "define main\n  say " + new string('(', 10000) + "1" + new string(')', 10000) + "\nend\n");
        try
        {
            RunResult ok = Run(root, wide, null);
            Assert.Equal(0, ok.Code);
            Assert.Contains("1", ok.StdOut);
            RunResult bad = Run(root, tooWide, null);
            Assert.Equal(1, bad.Code);
            Assert.Contains("expression is too deep", bad.StdErr);
        }
        finally
        {
            File.Delete(wide);
            File.Delete(tooWide);
        }
    }

    static RunResult Run(string root, string program, string budget)
    {
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        info.Arguments = "exec \"" + dll + "\" \"" + program + "\"";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        if (budget != null) info.Environment["VIRE_BUDGET"] = budget;
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(30000), "crash fixture timed out");
        return new RunResult(process.ExitCode, stdout, stderr);
    }

    static string RepoRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "tests.vire"))) return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root");
    }

    sealed class RunResult
    {
        public int Code;
        public string StdOut;
        public string StdErr;
        public RunResult(int code, string stdout, string stderr)
        {
            Code = code;
            StdOut = stdout;
            StdErr = stderr;
        }
    }
}
