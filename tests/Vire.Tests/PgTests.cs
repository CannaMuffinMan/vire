using System.IO;
using Xunit;

public class PgTests
{
    [Fact]
    public void PgLibraryDoesNotRaiseCapsOrWeakenSandbox()
    {
        string root = DualMode.FindRoot();
        string lib = File.ReadAllText(Path.Combine(root, "src", "rt-pg.vire"));
        Assert.Contains("PostgreSQL frontend/backend protocol v3", lib);
        Assert.Contains("SCRAM-SHA-256 is a residual", lib);
        Assert.Contains("pg_open", lib);
        Assert.Contains("pg_query", lib);
        Assert.Contains("pg_exec_param", lib);
        Assert.DoesNotContain("33554433", lib);
        Assert.DoesNotContain("100001", lib);
        Assert.DoesNotContain("5000001", lib);
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        Assert.Contains("pg-prove-windows.ps1", yml);
        Assert.Contains("native-pg-windows", yml);
        string ps = File.ReadAllText(Path.Combine(root, "tools", "pg-prove-windows.ps1"));
        Assert.Contains("VIRE_BUDGET", ps);
        Assert.Contains("5000000", ps);
        Assert.Contains("127.0.0.1", ps);
        Assert.Contains("ThrowawayVireCi1", ps);
        Assert.Contains("worktree add", ps);
        Assert.Contains("FAIL_BEFORE at", ps);
        Assert.Contains("5b10ea5fa5eea46859f17a52b36037d9d088c01d", ps);
        Assert.DoesNotContain("Set-MpPreference", ps);
        Assert.DoesNotContain("Add-MpPreference", ps);
        string guest = File.ReadAllText(Path.Combine(root, "tests", "native", "pg-client.vire"));
        Assert.Contains("SELECT 1", guest);
        Assert.Contains("CREATE TEMP TABLE", guest);
        Assert.Contains("SELECT FROM", guest);
        Assert.Contains("DROP TABLE u", guest);
        Assert.Contains("8.8.8.8", guest);
    }
}
