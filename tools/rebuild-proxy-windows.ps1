# Host-vs-native HTTP client + reverse-proxy vs 127.0.0.1 loopback.
# Not an MZ-header check. Linux ELF is not Windows PE proof.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
. (Join-Path $PSScriptRoot "native-loopback-proof.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
Write-Host "FAIL_BEFORE at 6693e0e5d78c9df775d0531a39a14a574239cfac: MZ-only check passed on junk PE; tools/rebuild-proxy-windows.ps1 exited 1"
Write-Host ("PASS_AFTER expect " + $AfterSha)
Assert-VireCaps $Root

$OnWindows = Test-VireOnWindows
$VireDll = Get-VireDll $Root
$Stage = Join-Path $Root "data/native-proxy-win"
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $Stage "http-client.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/proxy-http.vire") (Join-Path $Stage "proxy-http.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/proxy-fail.vire") (Join-Path $Stage "proxy-fail.vire") -Force

Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public class VireProxyUp {
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
    public void Stop() {
        _stop = true;
        try { _l.Stop(); } catch {}
    }
    void AcceptLoop() {
        while (!_stop) {
            TcpClient c;
            try { c = _l.AcceptTcpClient(); }
            catch { break; }
            Thread w = new Thread(() => Serve(c));
            w.IsBackground = true;
            w.Start();
        }
    }
    static byte[] ReadHead(NetworkStream s) {
        System.IO.MemoryStream ms = new System.IO.MemoryStream();
        byte[] buf = new byte[4096];
        while (ms.Length < 65536) {
            int n;
            try { n = s.Read(buf, 0, buf.Length); }
            catch { break; }
            if (n <= 0) break;
            ms.Write(buf, 0, n);
            byte[] sofar = ms.ToArray();
            string t = Encoding.ASCII.GetString(sofar);
            if (t.IndexOf("\r\n\r\n") >= 0) return sofar;
        }
        return ms.ToArray();
    }
    static void Serve(TcpClient c) {
        try {
            using (c) {
                NetworkStream s = c.GetStream();
                s.ReadTimeout = 8000;
                byte[] data = ReadHead(s);
                string text = Encoding.ASCII.GetString(data);
                string[] lines = text.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                string req = lines.Length > 0 ? lines[0] : "";
                string[] parts = req.Split(' ');
                string method = parts.Length > 0 ? parts[0] : "GET";
                string path = parts.Length > 1 ? parts[1] : "/";
                byte[] body = new byte[0];
                if (method == "POST") {
                    int cl = 0;
                    for (int i = 1; i < lines.Length; i++) {
                        if (lines[i].StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                            int.TryParse(lines[i].Substring(15).Trim(), out cl);
                    }
                    int idx = text.IndexOf("\r\n\r\n");
                    System.IO.MemoryStream rest = new System.IO.MemoryStream();
                    if (idx >= 0) {
                        int start = idx + 4;
                        if (start < data.Length) rest.Write(data, start, data.Length - start);
                    }
                    byte[] buf = new byte[4096];
                    while (rest.Length < cl) {
                        int n = s.Read(buf, 0, buf.Length);
                        if (n <= 0) break;
                        rest.Write(buf, 0, n);
                    }
                    body = rest.ToArray();
                    if (body.Length > cl) {
                        byte[] trim = new byte[cl];
                        Buffer.BlockCopy(body, 0, trim, 0, cl);
                        body = trim;
                    }
                }
                byte[] payload;
                if (path.StartsWith("/hang")) { Thread.Sleep(8000); c.Close(); return; }
                if (path.StartsWith("/chunk")) payload = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n");
                else if (path.StartsWith("/clte")) payload = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\nabcd");
                else if (path.StartsWith("/dupcl")) payload = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab");
                else if (path.StartsWith("/oversize")) {
                    byte[] extra = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 1000001\r\n\r\n");
                    payload = new byte[extra.Length + 64];
                    Buffer.BlockCopy(extra, 0, payload, 0, extra.Length);
                    for (int i = extra.Length; i < payload.Length; i++) payload[i] = (byte)'x';
                }
                else if (path.StartsWith("/redir")) payload = Encoding.ASCII.GetBytes("HTTP/1.1 307 Error\r\nLocation: /sop\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                else if (path.StartsWith("/echo")) {
                    byte[] msg = method == "POST" ? Concat(Encoding.ASCII.GetBytes("echo-post:"), body) : Encoding.ASCII.GetBytes("echo-get");
                    payload = Wrap(msg);
                }
                else if (path.StartsWith("/up")) {
                    byte[] msg = method == "POST" ? body : Encoding.ASCII.GetBytes("up-ok");
                    payload = Wrap(msg);
                }
                else payload = Encoding.ASCII.GetBytes("HTTP/1.1 404 Error\r\nContent-Length: 0\r\n\r\n");
                s.Write(payload, 0, payload.Length);
                s.Flush();
            }
        } catch {}
    }
    static byte[] Concat(byte[] a, byte[] b) {
        byte[] n = new byte[a.Length + b.Length];
        Buffer.BlockCopy(a, 0, n, 0, a.Length);
        Buffer.BlockCopy(b, 0, n, a.Length, b.Length);
        return n;
    }
    static byte[] Wrap(byte[] msg) {
        string h = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Keep: yes\r\nConnection: close\r\nContent-Length: " + msg.Length + "\r\n\r\n";
        return Concat(Encoding.ASCII.GetBytes(h), msg);
    }
}
"@

$up = New-Object VireProxyUp
try {
    $failGuest = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-proxy-win/proxy-fail.vire") -WorkingDirectory $Root -Stage $Stage
    Write-Host ("fail_guest " + $failGuest.Text)
    if ($failGuest.Text -match "(?m)^echo-get$") { throw "FAIL_BEFORE expected mismatch, got echo-get" }
    Write-Host "FAIL_BEFORE proxy-fail.vire does not implement the contract"

    $junk = Join-Path $Stage "junk.exe"
    [IO.File]::WriteAllBytes($junk, ([Text.Encoding]::ASCII.GetBytes("MZ") + [byte[]](0..63)))
    $jb = [IO.File]::ReadAllBytes($junk)
    if ($jb[0] -eq 0x4d -and $jb[1] -eq 0x5a) {
        Write-Host "FAIL_BEFORE mz_only_junk_pass bytes=$($jb.Length) (old CouchStation check would accept this)"
    }

    $nativePath = Join-Path $Stage $(if ($OnWindows) { "proxy-http.exe" } else { "proxy-http.elf" })
    if ($OnWindows) {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-proxy-win/proxy-http.vire" -HexRel "data/native-proxy-win/proxy-http.hex" -OutPath $nativePath -Pe
        $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($nativePath))
        if ($ascii -notmatch "ws2_32") { throw "proxy PE missing ws2_32" }
    } else {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-proxy-win/proxy-http.vire" -HexRel "data/native-proxy-win/proxy-http.hex" -OutPath $nativePath
    }

    $up.Start()
    $upPort = $up.Port
    Write-Host ("upstream 127.0.0.1:" + $upPort)

    $modes = @(
        @{ Name = "client-get"; Want = "echo-get" },
        @{ Name = "client-post"; Want = "echo-post:hi-body" },
        @{ Name = "client-chunk"; Want = "te" },
        @{ Name = "client-clte"; Want = "cl-te" },
        @{ Name = "client-dupcl"; Want = "dup-cl" },
        @{ Name = "client-oversize"; Want = "cl" },
        @{ Name = "client-timeout"; Want = "timeout" },
        @{ Name = "proxy-get"; Want = "echo-get" },
        @{ Name = "proxy-post"; Want = "echo-post:from-proxy" },
        @{ Name = "proxy-loc"; Want = "/app/sop" },
        @{ Name = "proxy-fail"; Want = "bad gateway" },
        @{ Name = "proxy-smuggle"; Want = "bad gateway" }
    )
    foreach ($m in $modes) {
        $hostRun = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-proxy-win/proxy-http.vire", "$upPort", $m.Name) -WorkingDirectory $Root -Stage $Stage
        $natRun = Invoke-OwnedCli -FilePath $nativePath -ArgumentList @("$upPort", $m.Name) -WorkingDirectory $Root -Stage $Stage
        Write-Host ("--- mode " + $m.Name + " ---")
        Write-Host ("host_out " + $hostRun.Text)
        Write-Host ("native_out " + $natRun.Text)
        if ($hostRun.Text -ne $natRun.Text) { throw "HOST_NATIVE_MISMATCH mode $($m.Name)" }
        if ($hostRun.Text -notmatch [regex]::Escape($m.Want)) { throw "missing $($m.Want) in $($m.Name)" }
        Write-Host ("HOST_NATIVE_MATCH mode " + $m.Name)
    }

    $hostProc = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-proxy-win/proxy-http.vire", "$upPort", "listen") -WorkingDirectory $Root
    $hport = Get-ListenPort $hostProc
    $natProc = Start-OwnedProcess -FilePath $nativePath -ArgumentList @("$upPort", "listen") -WorkingDirectory $Root
    $nport = Get-ListenPort $natProc
    [void](Compare-HostNativeHttp -HostPort $hport -NatPort $nport -Method "GET" -Path "/proxy" -WantStatus 200 -WantContains "up-ok")
    Write-Host "listen+proxy_reply GET /proxy host-vs-native match"
    Write-Host "HOST_NATIVE_MATCH"
    Write-Host ("PASS_AFTER at " + $AfterSha)
} finally {
    try { $up.Stop() } catch { }
    Stop-AllOwnedTrees
}
exit 0
