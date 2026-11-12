using System;
using System.Diagnostics;
using Xunit;

public class KdfKatTests
{
    [Fact]
    public void GuestBcryptCost4MatchesPublishedVectors()
    {
        string root = DualMode.FindRoot();
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        info.Arguments = "exec \"" + dll + "\" \"kdf-prove.vire\"";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_BUDGET"] = "5000000";
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(400000), "kdf-prove timed out");
        Assert.True(process.ExitCode == 0, stderr + stdout);
        string norm = DualMode.Norm(stdout);
        Assert.Contains("BCRYPT password cost4 PASS", norm);
        Assert.Contains("BCRYPT empty cost4 PASS", norm);
        Assert.Contains("BCRYPT utf8 cost4 PASS", norm);
        Assert.Contains("BCRYPT 72-byte truncation PASS", norm);
        Assert.Contains("BCRYPT wrong password REJECT", norm);
        Assert.Contains("not a CPU timing barrier", norm);
        Assert.Contains("KDF PROVE pass", norm);
    }
}
