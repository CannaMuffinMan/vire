using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildUnauthSidecarContractTests
{
    [Fact]
    public void UnauthSidecarGoldensMatchServiceScopedGuests()
    {
        string root = DualMode.FindRoot();
        Check(root, "rpc-portal-go", "rpc-portal-go.vire", "rpc-portal-go-fail.vire", "/api/capabilities", "node");
        Check(root, "rpc-portal-go", "rpc-portal-go.vire", "rpc-portal-go-fail.vire", "/api/rpc", "enabled");
        Check(root, "rpc-portal-go", "rpc-portal-go.vire", "rpc-portal-go-fail.vire", "/api/transfer", "value_transfer_disabled");
        Check(root, "edge-go", "edge-go.vire", "edge-go-fail.vire", "/healthz", "ok");
        Check(root, "edge-go", "edge-go-maintenance.vire", "edge-go-fail.vire", "/healthz", "maintenance_mode");
        Check(root, "dev-portal-go", "dev-portal-go.vire", "dev-portal-go-fail.vire", "/", "dist_missing");
        Check(root, "fcgbds-dashboard-go", "fcgbds-dashboard-go.vire", "fcgbds-dashboard-go-fail.vire", "/api/health", "fcgbds-dashboard");
        Check(root, "fcgbds-dashboard-go", "fcgbds-dashboard-go.vire", "fcgbds-dashboard-go-fail.vire", "/api/stream-wall/status", "scheduledUnlockAt");
        Check(root, "fcgbds-dashboard-go", "fcgbds-dashboard-go.vire", "fcgbds-dashboard-go-fail.vire", "/api/events-detailed", "Detailed events unavailable");

        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-unauth-sidecar-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "rpc-portal-go", "BLOCKED.md")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "edge-go", "BLOCKED.md")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "dev-portal-go", "BLOCKED.md")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "fcgbds-dashboard-go", "BLOCKED.md")));

        string sidecar = File.ReadAllText(Path.Combine(root, "tools", "rebuild-sidecar-diff.sh"));
        Assert.Contains("rebuild-unauth-sidecar-diff.sh", sidecar);

        string health = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "rpc-portal-go", "api-health.json"));
        using JsonDocument doc = JsonDocument.Parse(health);
        Assert.Equal(200, doc.RootElement.GetProperty("cases")[0].GetProperty("status").GetInt32());
        Assert.Equal("application/json", doc.RootElement.GetProperty("cases")[0].GetProperty("headers").GetProperty("content-type").GetString());
        Assert.DoesNotContain("charset", doc.RootElement.GetProperty("cases")[0].GetProperty("headers").GetProperty("content-type").GetString());
    }

    static void Check(string root, string service, string guestName, string failName, string path, string token)
    {
        string guest = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", guestName));
        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", failName));
        Assert.Contains("path == \"" + path + "\"", guest);
        Assert.Contains(token, guest);
        Assert.DoesNotContain(token, fail);
        Assert.True(Directory.Exists(Path.Combine(root, "tests", "rebuild", "contracts", service)));
    }
}
