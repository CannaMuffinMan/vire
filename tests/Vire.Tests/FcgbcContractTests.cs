using System;
using System.IO;
using System.Text.Json;
using Xunit;

public class FcgbcContractTests
{
    [Fact]
    public void FcgbcHeaderContractHasExactJsonContentType()
    {
        string root = DualMode.FindRoot();
        string path = Path.Combine(root, "tests", "rebuild", "contracts", "fcgbc", "headers.json");
        using JsonDocument doc = JsonDocument.Parse(File.ReadAllText(path));
        JsonElement jsonH = doc.RootElement.GetProperty("json_headers");
        JsonElement optH = doc.RootElement.GetProperty("options_headers");
        Assert.Equal("application/json", jsonH.GetProperty("content-type").GetString());
        Assert.DoesNotContain("charset", jsonH.GetProperty("content-type").GetString());
        Assert.False(optH.TryGetProperty("content-type", out _));
        Assert.Equal("*", jsonH.GetProperty("access-control-allow-origin").GetString());
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        Assert.Contains("Content-Type: application/json\\r\\nContent-Length:", net);
        Assert.DoesNotContain("application/json; charset=utf-8", net);
        string listen = File.ReadAllText(Path.Combine(root, "VireListen.cs"));
        // Landing/proxy stack uses ContentTypeOf (JSON is application/json with no charset).
        Assert.True(
            listen.IndexOf("Content-Type: application/json\\r\\n", StringComparison.Ordinal) >= 0
            || listen.IndexOf("ContentTypeOf", StringComparison.Ordinal) >= 0,
            "host listen must emit JSON Content-Type without charset");
        int jsonCases = 0;
        foreach (JsonElement c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            string kind = c.GetProperty("headers").GetString();
            if (kind == "json")
            {
                jsonCases++;
                Assert.Equal("application/json", jsonH.GetProperty("content-type").GetString());
            }
            else
            {
                Assert.Equal("options", kind);
                Assert.Equal(204, c.GetProperty("status").GetInt32());
            }
        }
        Assert.True(jsonCases >= 20);
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-fcgbc-diff.sh")));
    }
}
