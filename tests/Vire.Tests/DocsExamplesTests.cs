using System;
using System.Diagnostics;
using System.IO;
using Xunit;

public class DocsExamplesTests
{
    [Fact]
    public void CheckerRejectsABrokenExpectedFileThenPassesTheRealSet()
    {
        string root = DualMode.FindRoot();
        string script = Path.Combine(root, "tools", "check-docs-examples.sh");
        Assert.True(File.Exists(script));
        DualMode.Proc broken = Bash(root, "bash tools/check-docs-examples.sh --prove-broken");
        Assert.Equal(0, broken.Code);
        Assert.Contains("prove-broken: checker rejected the bad example", DualMode.Norm(broken.Out + broken.Err));
        DualMode.Proc ok = Bash(root, "bash tools/check-docs-examples.sh");
        Assert.True(ok.Code == 0, ok.Out + ok.Err);
        Assert.Contains("docs-examples ok", DualMode.Norm(ok.Out + ok.Err));
    }

    [Fact]
    public void WorkflowRunsDocsExamplesInBothModesAndProvesBroken()
    {
        string yml = File.ReadAllText(Path.Combine(DualMode.FindRoot(), ".github", "workflows", "check.yml"));
        Assert.Contains("docs-examples:", yml);
        Assert.Contains("tools/check-docs-examples.sh --prove-broken", yml);
        Assert.Contains("tools/check-docs-examples.sh", yml);
        Assert.Contains("dotnet-version: 10.0.x", yml);
    }

    static DualMode.Proc Bash(string root, string command)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = "bash";
        info.Arguments = "-lc \"" + command.Replace("\"", "\\\"") + "\"";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_SEAL_KEY"] = DualMode.TestKeyB64();
        info.Environment["VIRE_BUDGET"] = "5000000";
        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_ROOT");
        if (string.IsNullOrEmpty(dotnet))
            dotnet = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dotnet");
        if (Directory.Exists(dotnet) && path.IndexOf(dotnet, StringComparison.Ordinal) < 0)
            path = dotnet + Path.PathSeparator + path;
        info.Environment["PATH"] = path;
        if (Directory.Exists(dotnet)) info.Environment["DOTNET_ROOT"] = dotnet;
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(300000), "docs-examples checker timed out");
        return new DualMode.Proc(process.ExitCode, stdout, stderr);
    }
}
