using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildHealthContractTests
{
    [Fact]
    public void RecordedUnauthContractsMatchGuestHealthSource()
    {
        string root = DualMode.FindRoot();
        string guest = File.ReadAllText(Path.Combine(root, "guest-health.vire"));
        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "fail-before-health.vire"));
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        Assert.Contains("rt_net_statusof", net);
        Assert.Contains("StatusOf", net);

        CheckContract(root, "fcg-health.json", guest, new[] { "/health", "/api/health" });
        CheckContract(root, "fcg-info.json", guest, new[] { "/info" });
        CheckContract(root, "fcg-connect.json", guest, new[] { "/connect" });
        CheckContract(root, "fcg-payments.json", guest, new[] { "/payments", "/mine" });

        string healthJson = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "fcg-health.json"));
        using JsonDocument doc = JsonDocument.Parse(healthJson);
        foreach (JsonElement c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            if (c.GetProperty("name").GetString() != "get_nope") continue;
            Assert.Equal(404, c.GetProperty("status").GetInt32());
            Assert.False(c.TryGetProperty("native_http_status_note", out _));
            Assert.Contains(c.GetProperty("body").GetString().Replace("\"", "\\\""), guest);
        }
        Assert.DoesNotContain("path == \"/api/health\"", fail);
        Assert.DoesNotContain("path == \"/info\"", fail);
        Assert.DoesNotContain("path == \"/connect\"", fail);
        Assert.DoesNotContain("path == \"/payments\"", fail);
        Assert.DoesNotContain("path == \"/mine\"", fail);
        Assert.Contains("payments are off", guest);
        Assert.Contains("mining stays inside the app", guest);
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-health-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "docs", "REBUILD-MY-STACK.md")));
    }

    static void CheckContract(string root, string file, string guest, string[] paths)
    {
        string json = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", file));
        using JsonDocument doc = JsonDocument.Parse(json);
        JsonElement cases = doc.RootElement.GetProperty("cases");
        int n = 0;
        foreach (JsonElement c in cases.EnumerateArray())
        {
            n++;
            string path = c.GetProperty("path").GetString();
            string body = c.GetProperty("body").GetString();
            int status = c.GetProperty("status").GetInt32();
            if (status == 200)
            {
                Assert.Contains("path == \"" + path + "\"", guest);
                Assert.Contains(body.Replace("\"", "\\\""), guest);
            }
        }
        Assert.True(n >= paths.Length);
        foreach (string p in paths)
            Assert.Contains("path == \"" + p + "\"", guest);
    }
}
