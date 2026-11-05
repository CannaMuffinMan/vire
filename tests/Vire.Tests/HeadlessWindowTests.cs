using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using Xunit;

public class HeadlessWindowTests
{
    [Fact]
    public void HeadlessShowFinishesWorkSampleAndPrintsALine()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc proc = RunHeadless(root, new string[] { "work.vire" }, root);
        Assert.Equal(0, proc.Code);
        Assert.Contains("Write Vire - done", DualMode.Norm(proc.Out));
        Assert.DoesNotContain("0 close", DualMode.Norm(proc.Out));
    }

    static DualMode.Proc RunHeadless(string root, string[] args, string cwd)
    {
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        StringBuilder argv = new StringBuilder();
        argv.Append("exec \"").Append(dll).Append("\"");
        foreach (string arg in args)
            argv.Append(" \"").Append(arg.Replace("\"", "\\\"")).Append("\"");
        info.Arguments = argv.ToString();
        info.WorkingDirectory = cwd;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.RedirectStandardInput = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_HEADLESS"] = "1";
        info.Environment["VIRE_SEAL_KEY"] = DualMode.TestKeyB64();
        info.Environment["VIRE_BUDGET"] = "5000000";
        Process process = Process.Start(info);
        process.StandardInput.Close();
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(30000), "vire process timed out");
        return new DualMode.Proc(process.ExitCode, stdout + stderr, "");
    }
}
