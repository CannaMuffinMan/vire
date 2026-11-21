using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildLandingContractTests
{
    [Fact]
    public void RecordedLandingGoldensMatchGuestSources()
    {
        string root = DualMode.FindRoot();
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        Assert.Contains("txt_hdrs_html", net);
        Assert.Contains("emitLandingHttp", net);
        Assert.Contains("txt_hdrs_auth", net);
        string listen = File.ReadAllText(Path.Combine(root, "VireListen.cs"));
        Assert.Contains("text/html; charset=utf-8", listen);
        Assert.Contains("ExtraHeadersOf", listen);
        Assert.Contains("data_held", listen);
        Assert.Contains("307", listen);

        string guest = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "landing-go.vire"));
        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "landing-fail.vire"));
        Assert.Contains("path == \"/healthz\"", guest);
        Assert.Contains("path == \"/api/capabilities\"", guest);
        Assert.Contains("path == \"/api/couchy/status\"", guest);
        Assert.Contains("path == \"/api/live-popup\"", guest);
        Assert.Contains("path == \"/api/auth\"", guest);
        Assert.Contains("path == \"/api/internal/version\"", guest);
        Assert.Contains("path == \"/api/subscription\"", guest);
        Assert.Contains("Authentication required.", guest);
        Assert.Contains("data_held", guest);
        Assert.DoesNotContain("path == \"/healthz\"", fail);
        Assert.DoesNotContain("FCG_AUTH_COOKIE_SECRET", guest);
        Assert.DoesNotContain("shopify", guest);
        Assert.DoesNotContain("LANDING_UPSTREAM", guest);

        string dir = Path.Combine(root, "tests", "rebuild", "contracts", "landing-go");
        Assert.True(File.Exists(Path.Combine(dir, "healthz.json")));
        Assert.True(File.Exists(Path.Combine(dir, "api.json")));
        Assert.True(File.Exists(Path.Combine(dir, "redirects.json")));
        Assert.True(File.Exists(Path.Combine(dir, "held.json")));
        Assert.True(File.Exists(Path.Combine(dir, "pages.json")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-landing-diff.sh")));

        string healthz = File.ReadAllText(Path.Combine(dir, "healthz.json"));
        using (JsonDocument doc = JsonDocument.Parse(healthz))
        {
            JsonElement c = doc.RootElement.GetProperty("cases")[0];
            Assert.Equal(200, c.GetProperty("status").GetInt32());
            Assert.Equal("ok", c.GetProperty("body").GetString());
            Assert.Equal("text/plain; charset=utf-8", c.GetProperty("headers").GetProperty("content-type").GetString());
        }

        string api = File.ReadAllText(Path.Combine(dir, "api.json"));
        using (JsonDocument doc = JsonDocument.Parse(api))
        {
            int n = 0;
            foreach (JsonElement c in doc.RootElement.GetProperty("cases").EnumerateArray())
            {
                n++;
                string path = c.GetProperty("path").GetString();
                Assert.Contains("path == \"" + path + "\"", guest);
            }
            Assert.Equal(6, n);
        }

        string held = File.ReadAllText(Path.Combine(dir, "held.json"));
        using (JsonDocument doc = JsonDocument.Parse(held))
        {
            foreach (JsonElement c in doc.RootElement.GetProperty("cases").EnumerateArray())
            {
                Assert.Equal(503, c.GetProperty("status").GetInt32());
                Assert.Equal("{\"reason\":\"data_held\"}", c.GetProperty("body").GetString());
            }
        }

        string windows = File.ReadAllText(Path.Combine(root, "tools", "rebuild-fcgcpa-windows.ps1"));
        Assert.Contains("landing-go.vire", windows);
    }
}
