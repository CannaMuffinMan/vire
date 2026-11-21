using System.IO;
using Xunit;

public class RebuildProxyContractTests
{
    [Fact]
    public void LoopbackHttpAndProxyPrimitiveIsWired()
    {
        string root = DualMode.FindRoot();
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        string linux = File.ReadAllText(Path.Combine(root, "src", "rt-linux.vire"));
        string listen = File.ReadAllText(Path.Combine(root, "VireListen.cs"));
        string http = File.ReadAllText(Path.Combine(root, "src", "http-client.vire"));
        string guest = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "proxy-http.vire"));
        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "guests", "proxy-fail.vire"));
        Assert.Contains("txt_st502", net);
        Assert.Contains("land_st_502", net);
        Assert.Contains("4102", net);
        Assert.Contains("iat_ss", net);
        Assert.Contains("ss_timeval", linux);
        Assert.Contains("SO_RCVTIMEO", linux);
        Assert.Contains("502", listen);
        Assert.Contains("Bad Gateway", listen);
        Assert.Contains("define http with spec", http);
        Assert.Contains("define proxy with spec", http);
        Assert.Contains("define http_ws_intent with method, extra", http);
        Assert.Contains("sec-websocket-key", http);
        Assert.Contains("transfer-encoding", http);
        Assert.Contains("X-Forwarded-For", http);
        Assert.Contains("X-Forwarded-Host", http);
        Assert.Contains("X-Forwarded-Proto", http);
        Assert.Contains("127.0.0.1", http);
        Assert.DoesNotContain("LoadLibraryA", http);
        Assert.Contains("use \"http-client.vire\"", guest);
        Assert.Contains("client-get", guest);
        Assert.Contains("path == \"/proxy\"", guest);
        Assert.Contains("proxy_reply", guest);
        Assert.Contains("pr_body_ok", net);
        Assert.Contains("Unsigned sub of needle_len", net);
        Assert.Contains("proxy-ws", guest);
        Assert.DoesNotContain("define http with spec", fail);
        Assert.DoesNotContain("LANDING_UPSTREAM", guest);
        Assert.DoesNotContain("fcgcpa-prod", guest);
        Assert.True(File.Exists(Path.Combine(root, "tools", "proxy-reply-proof.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "proxy-reply-windows.ps1")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-proxy-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-proxy-windows.ps1")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-proxy-ws-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-proxy-ws-windows.ps1")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "proxy", "echo.json")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "proxy", "ws-echo.json")));
        string docs = File.ReadAllText(Path.Combine(root, "docs", "REBUILD-MY-STACK.md"));
        Assert.Contains("src/http-client.vire", docs);
        Assert.Contains("rebuild-proxy-diff.sh", docs);
        Assert.Contains("rebuild-proxy-ws-diff.sh", docs);
        Assert.Contains("65536", File.ReadAllText(Path.Combine(root, "src", "http-client.vire")));
        Assert.Equal(5000000, Program.ProgramStepCap);
    }
}
