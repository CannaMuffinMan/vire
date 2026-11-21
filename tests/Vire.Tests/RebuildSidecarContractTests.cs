using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildSidecarContractTests
{
    [Fact]
    public void RecordedSidecarGoldensMatchGuestSources()
    {
        string root = DualMode.FindRoot();
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        Assert.Contains("txt_hdrs_plain", net);
        Assert.Contains("rt_net_ctype", net);
        string listen = File.ReadAllText(Path.Combine(root, "VireListen.cs"));
        Assert.Contains("ContentTypeOf", listen);
        Assert.Contains("text/plain; charset=utf-8", listen);

        Check(root, "fcgbds-health.json", "fcgbds-health.vire", "fcgbds-fail.vire", "/health", "fcgbds-core");
        Check(root, "fcgbc-pending.json", "fcgbc-pending.vire", "fcgbc-fail.vire", "/pending-transactions", "[]");
        Check(root, "cpa-health.json", "cpa-health.vire", "cpa-fail.vire", "/health", "ok");
        Check(root, "rpc-health.json", "rpc-health.vire", "rpc-fail.vire", "/api/health", "\\\"ok\\\":true");
        Check(root, "api-healthz.json", "api-healthz.vire", "api-fail.vire", "/healthz", "\\\"live\\\":true");

        string cpa = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "cpa-health.json"));
        using JsonDocument doc = JsonDocument.Parse(cpa);
        JsonElement c = doc.RootElement.GetProperty("cases")[0];
        Assert.Equal("text/plain", c.GetProperty("headers").GetProperty("content-type").GetString());
        Assert.Equal("ok\n", c.GetProperty("body").GetString());

        string fcgbds = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "fcgbds-health.json"));
        using JsonDocument d2 = JsonDocument.Parse(fcgbds);
        JsonElement fields = d2.RootElement.GetProperty("cases")[0].GetProperty("body_fields");
        Assert.True(fields.GetProperty("ok").GetBoolean());
        Assert.Equal("fcgbds-core", fields.GetProperty("service").GetString());
        Assert.False(fields.GetProperty("paymentsEnabled").GetBoolean());
        Assert.False(d2.RootElement.GetProperty("cases")[0].TryGetProperty("body", out _));

        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-sidecar-diff.sh")));
    }

    static void Check(string root, string contract, string guestName, string failName, string path, string token)
    {
        string guest = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", guestName));
        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", failName));
        Assert.Contains("path == \"" + path + "\"", guest);
        Assert.Contains(token, guest);
        Assert.DoesNotContain(token, fail);
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", contract)));
    }
}
