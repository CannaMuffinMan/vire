using System;
using System.IO;
using Xunit;

public class TimeTests
{
    [Fact]
    public void HostUnixIsUtcSecondsAfter2026()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc run = DualMode.RunVire(root, new string[] { "tests/native/time-unix.vire" }, root);
        Assert.True(run.Code == 0, run.Err + run.Out);
        string outp = DualMode.Norm(run.Out);
        Assert.True(int.TryParse(outp.Trim(), out int sec), outp);
        Assert.True(sec > 1767225600, "unix " + sec);
        long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        Assert.InRange(sec, now - 300, now + 300);
    }

    [Fact]
    public void TimeProveGuestPassesOnHost()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc run = DualMode.RunVire(root, new string[] { "time-prove.vire" }, root);
        Assert.True(run.Code == 0, run.Err + run.Out);
        string outp = DualMode.Norm(run.Out);
        Assert.Contains("TIME PROVE pass", outp);
        Assert.Contains("EXPIRED JWT REJECT", outp);
        Assert.Contains("VALID EXP JWT ACCEPT", outp);
        Assert.DoesNotContain("EXPIRED JWT ACCEPT", outp);
    }

    [Fact]
    public void TimeSourcesDoNotRaiseCapsOrWeakenSandbox()
    {
        string root = DualMode.FindRoot();
        string lib = File.ReadAllText(Path.Combine(root, "src", "rt-time.vire"));
        Assert.Contains("GetSystemTimeAsFileTime", File.ReadAllText(Path.Combine(root, "src", "pe.vire")));
        Assert.Contains("emitTimeRuntime", lib);
        Assert.Contains("rt_unix", lib);
        Assert.DoesNotContain("33554433", lib);
        Assert.DoesNotContain("100001", lib);
        Assert.DoesNotContain("LoadLibraryA", lib);
        Assert.DoesNotContain("Set-MpPreference", lib);
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        Assert.Contains("time-prove-windows.ps1", yml);
        string ps = File.ReadAllText(Path.Combine(root, "tools", "time-prove-windows.ps1"));
        Assert.Contains("5b10ea5fa5eea46859f17a52b36037d9d088c01d", ps);
        Assert.Contains("FAIL_BEFORE", ps);
        Assert.Contains("1767225600", ps);
        Assert.Contains("VIRE_BUDGET", ps);
        Assert.Contains("5000000", ps);
        Assert.DoesNotContain("Set-MpPreference", ps);
        Assert.True(File.Exists(Path.Combine(root, "tests", "native", "time-prove.vire")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "native", "time-unix.vire")));
    }
}
