using System.IO;
using System.Text.Json;
using Xunit;

public class RebuildFcgbdsWorkerContractTests
{
    [Fact]
    public void FcgbdsAndWorkerContractsMatchGuestSources()
    {
        string root = DualMode.FindRoot();
        string guest = File.ReadAllText(Path.Combine(root, "guest-fcgbds.vire"));
        string worker = File.ReadAllText(Path.Combine(root, "guest-worker.vire"));
        string failHttp = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "fail-before-fcgbds.vire"));
        string failWorker = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "fail-before-worker.vire"));

        Assert.Contains("fcgbds-core", guest);
        Assert.Contains("path == \"/healthz\"", guest);
        Assert.Contains("path == \"/api/bot-defense/stats\"", guest);
        Assert.Contains("path == \"/api/bot-defense/events\"", guest);
        Assert.Contains("path == \"/api/fcgbds/bridge/spec\"", guest);
        Assert.Contains("refusing reserved port", guest);
        Assert.Contains("7099", guest);
        Assert.Contains("8778", guest);
        Assert.DoesNotContain("path == \"/healthz\"", failHttp);

        string json = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "fcgbds-go.json"));
        using JsonDocument doc = JsonDocument.Parse(json);
        int n = 0;
        foreach (JsonElement c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            n++;
            string path = c.GetProperty("path").GetString();
            int q = path.IndexOf('?');
            if (q >= 0) path = path.Substring(0, q);
            Assert.Contains(path, guest);
        }
        Assert.Equal(25, n);

        Assert.Contains("PAYMENTS_ENABLED must stay false", worker);
        Assert.Contains("worker-go registered jobs disabled", worker);
        Assert.Contains("refusing to start jobs: skeleton only", worker);
        Assert.DoesNotContain("PAYMENTS_ENABLED must stay false", failWorker);

        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-fcgbds-worker-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-fcgbds-worker-windows.ps1")));
        Assert.DoesNotContain("railway.internal", guest);
        Assert.DoesNotContain("railway.internal", worker);
    }
}
