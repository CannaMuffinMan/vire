using System.IO;
using Xunit;

public class RedisTests
{
    [Fact]
    public void RedisLibraryKeepsCapsAndAddsRedissVerifyFull()
    {
        string root = DualMode.FindRoot();
        string lib = File.ReadAllText(Path.Combine(root, "src", "rt-redis.vire"));
        Assert.Contains("rediss://", lib);
        Assert.Contains("redis_open_tls", lib);
        Assert.Contains("redis_open_rediss", lib);
        Assert.Contains("tls_connect", lib);
        Assert.Contains("tls_send", lib);
        Assert.Contains("redis_auth_tls", lib);
        Assert.Contains("plaintext redis url", lib);
        Assert.Contains("loopback only", lib);
        Assert.DoesNotContain("33554433", lib);
        Assert.DoesNotContain("100001", lib);
        Assert.DoesNotContain("5000001", lib);
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        Assert.Contains("redis-tls-prove-windows.ps1", yml);
        Assert.Contains("native-redis-tls-windows", yml);
        string tlsPs = File.ReadAllText(Path.Combine(root, "tools", "redis-tls-prove-windows.ps1"));
        Assert.Contains("VIRE_BUDGET", tlsPs);
        Assert.Contains("5000000", tlsPs);
        Assert.Contains("127.0.0.1", tlsPs);
        Assert.Contains("f085dff6770513cfc9660f1a712967e177cf5b50", tlsPs);
        Assert.Contains("tls-port", tlsPs);
        Assert.DoesNotContain("Set-MpPreference", tlsPs);
        string tlsSh = File.ReadAllText(Path.Combine(root, "tools", "redis-tls-prove-linux.sh"));
        Assert.Contains("verify-full", tlsSh);
        Assert.Contains("127.0.0.1", tlsSh);
        Assert.Contains("compile-native.vire", tlsSh);
        Assert.Contains(" elf", tlsSh);
        Assert.DoesNotContain("Set-MpPreference", tlsSh);
        string guest = File.ReadAllText(Path.Combine(root, "tests", "native", "redis-tls.vire"));
        Assert.Contains("redis_open_rediss", guest);
        Assert.Contains("PING", guest);
        Assert.Contains("SET", guest);
        Assert.Contains("GET", guest);
        Assert.Contains("8.8.8.8", guest);
        string verify = File.ReadAllText(Path.Combine(root, "tests", "native", "redis-tls-verify.vire"));
        Assert.Contains("evil.example", verify);
        Assert.Contains("redis-untrusted.pem", verify);
        Assert.Contains("expired-cert", verify);
        Assert.Contains("EXP_PORT_PLACEHOLDER", verify);
        string neg = File.ReadAllText(Path.Combine(root, "tests", "native", "redis-tls-neg.vire"));
        Assert.Contains("plaintext downgrade", neg);
        string rebuild = File.ReadAllText(Path.Combine(root, "docs", "REBUILD-MY-STACK.md"));
        Assert.Contains("rediss://", rebuild);
        Assert.Contains("What this PR does not prove", rebuild);
    }
}
