using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildFcgbdsHeartbeatContractTests
{
    [Fact]
    public void HeartbeatJsonContractMatchesGuestAndFailBefore()
    {
        string root = DualMode.FindRoot();
        string guest = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "fcgbds-heartbeat.vire"));
        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "fcgbds-heartbeat-fail.vire"));
        string json = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "fcgbds-heartbeat.json"));
        using JsonDocument doc = JsonDocument.Parse(json);
        Assert.Equal("fcgbds-heartbeat-json", doc.RootElement.GetProperty("id").GetString());
        int n = 0;
        foreach (JsonElement c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            n++;
            Assert.Equal("POST", c.GetProperty("method").GetString());
            Assert.Equal("/api/bot-defense/reviewers/heartbeat", c.GetProperty("path").GetString());
        }
        Assert.Equal(3, n);
        Assert.Contains("session_id with body", guest);
        Assert.Contains("sessionId", guest);
        Assert.Contains("listen with 0", guest);
        Assert.DoesNotContain("session_id with body", fail);
        Assert.Contains("sessionId=", fail);
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-fcgbds-heartbeat-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-fcgbds-heartbeat-windows.ps1")));
        Assert.DoesNotContain("FCGBC", guest);
        Assert.DoesNotContain("railway.internal", guest);
    }
}
