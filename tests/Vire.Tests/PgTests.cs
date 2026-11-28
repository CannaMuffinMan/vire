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
        Assert.Contains("SCRAM-SHA-256", lib);
        Assert.Contains("SSLRequest", lib);
        Assert.Contains("verify-full", lib);
        Assert.Contains("pg_open_ssl", lib);
        Assert.Contains("tls_wrap", lib);
        Assert.Contains("pg_open", lib);
        Assert.Contains("pg_query", lib);
        Assert.Contains("pg_exec_param", lib);
        Assert.Contains("pg_begin", lib);
        Assert.Contains("pg_pbkdf2", lib);
        Assert.DoesNotContain("33554433", lib);
        Assert.DoesNotContain("100001", lib);
        Assert.DoesNotContain("5000001", lib);
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        Assert.Contains("pg-prove-windows.ps1", yml);
        Assert.Contains("native-pg-windows", yml);
        Assert.Contains("pg-tls-prove-windows.ps1", yml);
        Assert.Contains("pg-redis-tls-windows.ps1", yml);
        Assert.Contains("native-pg-tls-windows", yml);
        string tlsPs = File.ReadAllText(Path.Combine(root, "tools", "pg-tls-prove-windows.ps1"));
        Assert.Contains("VIRE_BUDGET", tlsPs);
        Assert.Contains("5000000", tlsPs);
        Assert.Contains("127.0.0.1", tlsPs);
        Assert.Contains("secur32.dll", tlsPs);
        Assert.Contains("cd0bd38584e4d3faad0f46b4eefe98515b2dbf26", tlsPs);
        Assert.Contains("pg-tls-stub", tlsPs);
        Assert.DoesNotContain("Set-MpPreference", tlsPs);
        string ps = File.ReadAllText(Path.Combine(root, "tools", "pg-prove-windows.ps1"));
        Assert.Contains("VIRE_BUDGET", ps);
        Assert.Contains("5000000", ps);
        Assert.Contains("127.0.0.1", ps);
        Assert.Contains("ThrowawayVireCi1", ps);
        Assert.Contains("worktree add", ps);
        Assert.Contains("FAIL_BEFORE at", ps);
        Assert.Contains("5b10ea5fa5eea46859f17a52b36037d9d088c01d", ps);
        Assert.Contains("scram-sha-256", ps);
        Assert.Contains("pg_secret_len", ps);
        Assert.DoesNotContain("Set-MpPreference", ps);
        Assert.DoesNotContain("Add-MpPreference", ps);
        string guest = File.ReadAllText(Path.Combine(root, "tests", "native", "pg-client.vire"));
        Assert.Contains("SELECT 1", guest);
        Assert.Contains("CREATE TEMP TABLE", guest);
        Assert.Contains("SELECT FROM", guest);
        Assert.Contains("DROP TABLE u", guest);
        Assert.Contains("8.8.8.8", guest);
        Assert.Contains("pg_begin", guest);
        Assert.Contains("pg_exec_param", guest);
        string sh = File.ReadAllText(Path.Combine(root, "tools", "pg-prove-linux.sh"));
        Assert.Contains("compile-native.vire", sh);
        Assert.Contains(" elf", sh);
        Assert.Contains("pg-decode-prove.vire", sh);
        string tlsSh = File.ReadAllText(Path.Combine(root, "tools", "pg-tls-prove-linux.sh"));
        Assert.Contains("sslmode", File.ReadAllText(Path.Combine(root, "src", "rt-pg.vire")) + tlsSh);
        Assert.Contains("verify-full", tlsSh);
        Assert.Contains("ssl-refused", File.ReadAllText(Path.Combine(root, "tests", "native", "pg-tls-neg.vire")));
        Assert.Contains("127.0.0.1", tlsSh);
        Assert.DoesNotContain("Set-MpPreference", tlsSh);
        string tlsGuest = File.ReadAllText(Path.Combine(root, "tests", "native", "pg-tls.vire"));
        Assert.Contains("pg_open_ssl", tlsGuest);
        Assert.Contains("SELECT 1", tlsGuest);
        Assert.Contains("verify-full", tlsGuest);
        string tlsVerify = File.ReadAllText(Path.Combine(root, "tests", "native", "pg-tls-verify.vire"));
        Assert.Contains("evil.example", tlsVerify);
        Assert.Contains("pg-untrusted.pem", tlsVerify);
        string decode = File.ReadAllText(Path.Combine(root, "pg-decode-prove.vire"));
        Assert.Contains("truncated", decode);
        Assert.Contains("oversize", decode);
        Assert.Contains("nonce mismatch", decode);
    }
}
