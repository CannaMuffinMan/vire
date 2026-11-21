using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildSopProxyContractTests
{
    [Fact]
    public void SopCookieAndLoopbackProxyContractsAreRecorded()
    {
        string root = DualMode.FindRoot();
        string sop = File.ReadAllText(Path.Combine(root, "src", "sop-cookie.vire"));
        Assert.Contains("define sop_issue", sop);
        Assert.Contains("define sop_verify", sop);
        Assert.Contains("ct_eq", sop);
        Assert.Contains("fcg_sop_authenticated", sop);
        Assert.DoesNotContain("FCG_AUTH_COOKIE_SECRET", sop);

        string guest = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "landing-sop.vire"));
        Assert.Contains("sop_verify", guest);
        Assert.DoesNotContain("forevercouchgang", guest);
        string landingProxy = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "landing-proxy.vire"));
        Assert.Contains("/api/upstream/echo", landingProxy);
        Assert.Contains("/api/gateway-down", landingProxy);

        string portal = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "dev-portal-go.vire"));
        Assert.Contains("/fcg-api/echo", portal);
        Assert.Contains("dist_missing", portal);
        Assert.Contains("not_configured", portal);

        string edge = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "edge-go.vire"));
        Assert.Contains("/healthz", edge);
        Assert.Contains("railway.internal", edge); // comment only: stays blocked
        Assert.Contains("www.fixture.test", edge);
        Assert.DoesNotContain("forevercouchgang.space", edge);

        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "sop-fail.vire"));
        Assert.Contains("not gated", fail);
        Assert.Contains("not proxied", fail);

        using (JsonDocument doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "landing-go", "sop-cookie.json"))))
        {
            Assert.Equal("ct_eq on 32-byte digest", doc.RootElement.GetProperty("security").GetProperty("compare").GetString());
            Assert.Equal(401, doc.RootElement.GetProperty("cases")[0].GetProperty("status").GetInt32());
        }
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "landing-go", "sop-proxy.json")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "dev-portal-go.json")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "edge-go.json")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-sop-proxy-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-sop-proxy-windows.ps1")));
        string stack = File.ReadAllText(Path.Combine(root, "docs", "REBUILD-MY-STACK.md"));
        Assert.Contains("SOP HMAC cookie", stack);
        Assert.Contains("rebuild-sop-proxy-diff.sh", stack);
    }
}
