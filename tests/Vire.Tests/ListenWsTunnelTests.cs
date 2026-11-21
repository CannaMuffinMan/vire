using System.IO;
using Xunit;

public class ListenWsTunnelTests
{
    [Fact]
    public void WsIntentRejectsNonWebsocketUpgradeAndBadKey()
    {
        Assert.Equal(-1, VireListen.WsIntent("GET", "GET /x HTTP/1.1\r\nUpgrade: h2c\r\nConnection: Upgrade"));
        Assert.Equal(-1, VireListen.WsIntent("POST", "POST /x HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13"));
        Assert.Equal(-1, VireListen.WsIntent("GET", "GET /x HTTP/1.1\r\nUpgrade: websocket\r\nConnection: close\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13"));
        Assert.Equal(-1, VireListen.WsIntent("GET", "GET /x HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: not-base64!!!!!!!!!!!!!!\r\nSec-WebSocket-Version: 13"));
        Assert.Equal(0, VireListen.WsIntent("GET", "GET /x HTTP/1.1\r\nHost: x"));
        Assert.Equal(1, VireListen.WsIntent("GET", "GET /x HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13"));
    }

    [Fact]
    public void ListenWsSourcesAndHarnessAreWired()
    {
        string root = DualMode.FindRoot();
        string listen = File.ReadAllText(Path.Combine(root, "VireListen.cs"));
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        Assert.Contains("TryWsHijack", listen);
        Assert.DoesNotContain("headers.Path != \"/ws/refuse\"", listen);
        Assert.Contains("wsIntent == 1 && code == 101", listen);
        Assert.Contains("Switching Protocols", listen);
        Assert.Contains("land_ws_send", net);
        Assert.Contains("txt_st101", net);
        Assert.Contains("land_ws_gate", net);
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-listen-ws-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-listen-wss-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "listen-ws-windows.ps1")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "guests", "listen-ws.vire")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "guests", "listen-ws-tls.vire")));
        string docs = File.ReadAllText(Path.Combine(root, "docs", "REBUILD-MY-STACK.md"));
        Assert.Contains("rebuild-listen-ws-diff.sh", docs);
        Assert.DoesNotContain("LoadLibraryA", listen);
        Assert.Equal(5000000, Program.ProgramStepCap);
    }
}
