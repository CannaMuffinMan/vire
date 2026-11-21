using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildPortalContractTests
{
    [Fact]
    public void PortalJwtStaticContractsAreRecorded()
    {
        string root = DualMode.FindRoot();
        string listen = File.ReadAllText(Path.Combine(root, "VireListen.cs"));
        Assert.Contains("405", listen);
        Assert.Contains("txt_st405", File.ReadAllText(Path.Combine(root, "src", "rt-net.vire")));

        string dist = File.ReadAllText(Path.Combine(root, "src", "dist-static.vire"));
        Assert.Contains("dist_has_bad", dist);
        Assert.Contains("..", dist);
        Assert.DoesNotContain("forevercouchgang", dist);

        string jwt = File.ReadAllText(Path.Combine(root, "src", "portal-jwt.vire"));
        Assert.Contains("jwt_hs256_verify", jwt);
        Assert.DoesNotContain("JWT_SECRET", jwt);
        string crypto = File.ReadAllText(Path.Combine(root, "src", "rt-crypto.vire"));
        Assert.Contains("cookie_line_end", crypto);

        string rpc = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "rpc-portal-go.vire"));
        Assert.Contains("/api/dev/auth", rpc);
        Assert.Contains("method_not_allowed", rpc);
        Assert.DoesNotContain("RPC_ADMIN_PASSWORD", rpc);

        string portal = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "dev-portal-go.vire"));
        Assert.Contains("dev_session", portal);
        Assert.Contains("redir_login", portal);
        Assert.Contains("/login", portal);
        Assert.Contains("method, path, body, head", portal);

        string dash = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "fcgbds-dashboard-go.vire"));
        Assert.Contains("fcgbds-dashboard", dash);
        Assert.Contains("/obs", dash);
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        Assert.Contains("Unsigned sub of needle_len", net);

        using (JsonDocument doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "rpc-portal-go.json"))))
        {
            Assert.Equal(401, doc.RootElement.GetProperty("cases")[3].GetProperty("status").GetInt32());
        }
        Assert.True(File.Exists(Path.Combine(root, "data", "rebuild-dist", "index.html")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-portal-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-portal-windows.ps1")));
        string stack = File.ReadAllText(Path.Combine(root, "docs", "REBUILD-MY-STACK.md"));
        Assert.Contains("8a", stack);
        Assert.Contains("rebuild-portal-diff.sh", stack);
    }
}
