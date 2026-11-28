# Host-vs-native RFC 6455 upgrade through reverse-proxy vs loopback echo.
# Linux ELF is not Windows PE proof.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
. (Join-Path $PSScriptRoot "native-loopback-proof.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
Write-Host "FAIL_BEFORE at 6693e0e5d78c9df775d0531a39a14a574239cfac: tools/rebuild-proxy-ws-windows.ps1 stub exit 1; MZ-only is not a WS proof"
Write-Host ("PASS_AFTER expect " + $AfterSha)
Assert-VireCaps $Root

$OnWindows = Test-VireOnWindows
$VireDll = Get-VireDll $Root
$Stage = Join-Path $Root "data/native-proxy-ws-win"
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $Stage "http-client.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/proxy-http.vire") (Join-Path $Stage "proxy-http.vire") -Force

Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
public class VireWsUp {
    const string WsGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    TcpListener _l;
    volatile bool _stop;
    public int Port;
    public void Start() {
        _l = new TcpListener(IPAddress.Loopback, 0);
        _l.Start();
        Port = ((IPEndPoint)_l.LocalEndpoint).Port;
        Thread t = new Thread(AcceptLoop);
        t.IsBackground = true;
        t.Start();
    }
    public void Stop() { _stop = true; try { _l.Stop(); } catch {} }
    void AcceptLoop() {
        while (!_stop) {
            TcpClient c;
            try { c = _l.AcceptTcpClient(); } catch { break; }
            Thread w = new Thread(() => Serve(c));
            w.IsBackground = true;
            w.Start();
        }
    }
    static string Hdr(string[] lines, string name) {
        string want = name.ToLower() + ":";
        for (int i = 1; i < lines.Length; i++) {
            if (lines[i].ToLower().StartsWith(want)) return lines[i].Substring(lines[i].IndexOf(':') + 1).Trim();
        }
        return "";
    }
    static bool HasToken(string value, string token) {
        string[] parts = value.Split(',');
        for (int i = 0; i < parts.Length; i++) {
            if (parts[i].Trim().ToLower() == token.ToLower()) return true;
        }
        return false;
    }
    static byte[] ReadExact(NetworkStream s, System.IO.MemoryStream buf, int n) {
        while (buf.Length < n) {
            byte[] tmp = new byte[4096];
            int r;
            try { r = s.Read(tmp, 0, tmp.Length); } catch { return null; }
            if (r <= 0) return null;
            buf.Write(tmp, 0, r);
        }
        return buf.ToArray();
    }
    static void Serve(TcpClient c) {
        try {
            using (c) {
                NetworkStream s = c.GetStream();
                s.ReadTimeout = 5000;
                byte[] data = new byte[16384];
                int n = s.Read(data, 0, data.Length);
                string text = Encoding.ASCII.GetString(data, 0, n);
                int split = text.IndexOf("\r\n\r\n");
                if (split < 0) { c.Close(); return; }
                string[] lines = text.Substring(0, split).Split(new string[] { "\r\n" }, StringSplitOptions.None);
                string req = lines.Length > 0 ? lines[0] : "";
                string[] parts = req.Split(' ');
                string path = parts.Length > 1 ? parts[1] : "/";
                string method = parts.Length > 0 ? parts[0] : "GET";
                if (path.StartsWith("/ws/refuse")) {
                    byte[] body = Encoding.ASCII.GetBytes("forbidden");
                    byte[] h = Encoding.ASCII.GetBytes("HTTP/1.1 403 Error\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
                    s.Write(h, 0, h.Length); s.Write(body, 0, body.Length); return;
                }
                if (!path.StartsWith("/ws/")) {
                    byte[] nf = Encoding.ASCII.GetBytes("HTTP/1.1 404 Error\r\nContent-Length: 0\r\n\r\n");
                    s.Write(nf, 0, nf.Length); return;
                }
                string upgrade = Hdr(lines, "upgrade");
                string connection = Hdr(lines, "connection");
                string key = Hdr(lines, "sec-websocket-key");
                string version = Hdr(lines, "sec-websocket-version");
                if (method != "GET" || !HasToken(upgrade, "websocket") || !HasToken(connection, "upgrade") || version != "13" || key.Length != 24) {
                    byte[] bad = Encoding.ASCII.GetBytes("HTTP/1.1 400 Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    s.Write(bad, 0, bad.Length); return;
                }
                string accept;
                using (SHA1 sha = SHA1.Create()) {
                    accept = Convert.ToBase64String(sha.ComputeHash(Encoding.ASCII.GetBytes(key + WsGuid)));
                }
                byte[] ok = Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n");
                s.Write(ok, 0, ok.Length);
                int restOff = split + 4;
                System.IO.MemoryStream buf = new System.IO.MemoryStream();
                if (restOff < n) buf.Write(data, restOff, n - restOff);
                while (true) {
                    byte[] cur = ReadExact(s, buf, 2);
                    if (cur == null) break;
                    int b0 = cur[0]; int b1 = cur[1];
                    int op = b0 & 0x0F;
                    bool masked = (b1 & 0x80) != 0;
                    int ln = b1 & 0x7F;
                    int off = 2;
                    if (ln == 126) {
                        cur = ReadExact(s, buf, 4);
                        if (cur == null) break;
                        ln = (cur[2] << 8) | cur[3];
                        off = 4;
                    } else if (ln == 127) { return; }
                    int need = off + (masked ? 4 : 0) + ln;
                    cur = ReadExact(s, buf, need);
                    if (cur == null) break;
                    byte[] payload = new byte[ln];
                    int po = off;
                    if (masked) {
                        byte[] mask = new byte[4];
                        Buffer.BlockCopy(cur, off, mask, 0, 4);
                        po = off + 4;
                        for (int i = 0; i < ln; i++) payload[i] = (byte)(cur[po + i] ^ mask[i & 3]);
                    } else {
                        Buffer.BlockCopy(cur, po, payload, 0, ln);
                    }
                    long leftover = buf.Length - need;
                    buf = new System.IO.MemoryStream();
                    if (leftover > 0) buf.Write(cur, need, (int)leftover);
                    if (op == 8) { s.Write(new byte[] { 0x88, 0x00 }, 0, 2); break; }
                    if (op == 9) {
                        byte[] ping = new byte[2 + ln];
                        ping[0] = 0x8A; ping[1] = (byte)ln;
                        Buffer.BlockCopy(payload, 0, ping, 2, ln);
                        s.Write(ping, 0, ping.Length); continue;
                    }
                    if (op == 1 || op == 2) {
                        byte[] fr;
                        if (ln < 126) {
                            fr = new byte[2 + ln];
                            fr[0] = (byte)(0x80 | op); fr[1] = (byte)ln;
                            Buffer.BlockCopy(payload, 0, fr, 2, ln);
                        } else {
                            fr = new byte[4 + ln];
                            fr[0] = (byte)(0x80 | op); fr[1] = 126;
                            fr[2] = (byte)((ln >> 8) & 0xFF); fr[3] = (byte)(ln & 0xFF);
                            Buffer.BlockCopy(payload, 0, fr, 4, ln);
                        }
                        s.Write(fr, 0, fr.Length);
                    }
                }
            }
        } catch {}
    }
}
"@

$up = New-Object VireWsUp
try {
    $nativePath = Join-Path $Stage $(if ($OnWindows) { "proxy-http.exe" } else { "proxy-http.elf" })
    if ($OnWindows) {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-proxy-ws-win/proxy-http.vire" -HexRel "data/native-proxy-ws-win/proxy-http.hex" -OutPath $nativePath -Pe
    } else {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-proxy-ws-win/proxy-http.vire" -HexRel "data/native-proxy-ws-win/proxy-http.hex" -OutPath $nativePath
    }
    $up.Start()
    Write-Host ("upstream 127.0.0.1:" + $up.Port)
    $checks = @(
        @{ Mode = "proxy-ws"; Want = "810268698800" },
        @{ Mode = "proxy-ws"; Want = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" },
        @{ Mode = "proxy-ws-bad"; Want = "400" },
        @{ Mode = "proxy-ws-refuse"; Want = "403" }
    )
    foreach ($c in $checks) {
        $hostRun = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-proxy-ws-win/proxy-http.vire", "$($up.Port)", $c.Mode) -WorkingDirectory $Root -Stage $Stage
        $natRun = Invoke-OwnedCli -FilePath $nativePath -ArgumentList @("$($up.Port)", $c.Mode) -WorkingDirectory $Root -Stage $Stage
        Write-Host ("--- mode " + $c.Mode + " ---")
        Write-Host ("host_out " + $hostRun.Text)
        Write-Host ("native_out " + $natRun.Text)
        if ($hostRun.Text -ne $natRun.Text) { throw "HOST_NATIVE_MISMATCH mode $($c.Mode)" }
        if ($hostRun.Text -notmatch [regex]::Escape($c.Want)) { throw "missing $($c.Want) in $($c.Mode)" }
        Write-Host ("HOST_NATIVE_MATCH mode " + $c.Mode)
    }
    Write-Host "HOST_NATIVE_MATCH"
    Write-Host ("PASS_AFTER at " + $AfterSha)
} finally {
    try { $up.Stop() } catch { }
    Stop-AllOwnedTrees
}
exit 0
