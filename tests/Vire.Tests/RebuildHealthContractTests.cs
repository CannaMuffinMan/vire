using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildHealthContractTests
{
    [Fact]
    public void RecordedHealthContractMatchesGuestHealthSource()
    {
        string root = DualMode.FindRoot();
        string json = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "fcg-health.json"));
        using JsonDocument doc = JsonDocument.Parse(json);
        JsonElement cases = doc.RootElement.GetProperty("cases");
        string guest = File.ReadAllText(Path.Combine(root, "guest-health.vire"));
        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "fail-before-health.vire"));
        string wantBody = null;
        foreach (JsonElement c in cases.EnumerateArray())
        {
            string name = c.GetProperty("name").GetString();
            string path = c.GetProperty("path").GetString();
            string body = c.GetProperty("body").GetString();
            int status = c.GetProperty("status").GetInt32();
            if (name == "get_health" || name == "get_api_health")
            {
                Assert.Equal(200, status);
                Assert.Contains("path == \"" + path + "\"", guest);
                Assert.Contains(body.Replace("\"", "\\\""), guest);
                wantBody = body;
            }
            if (name == "get_nope")
            {
                Assert.Contains(body.Replace("\"", "\\\""), guest);
                Assert.True(c.TryGetProperty("native_http_status_note", out JsonElement note));
                Assert.False(string.IsNullOrWhiteSpace(note.GetString()));
            }
        }
        Assert.False(string.IsNullOrEmpty(wantBody));
        Assert.DoesNotContain(wantBody.Replace("\"", "\\\""), fail);
        Assert.DoesNotContain("path == \"/api/health\"", fail);
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-health-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "docs", "REBUILD-MY-STACK.md")));
    }
}
