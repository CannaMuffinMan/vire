# CouchStation Windows PE: listen-side RFC 6455 Upgrade hijack.
# Host interpreter vs native PE transcripts. Loopback only.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "a64cfe5fdb398ac7c8049bd41ac431d780a0b09e"
Write-Host ("FAIL_BEFORE at " + $FailBefore + ": packed ELF accepted GET /ws/refuse with 101")
Write-Host ("PASS_AFTER expect " + $AfterSha)

$rt = Get-Content -Raw (Join-Path $Root "src/rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}

$stage = Join-Path $Root "data/native-listen-ws"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Root "tests/rebuild/guests/listen-ws.vire") (Join-Path $stage "listen-ws.vire") -Force
$hex = Join-Path $stage "listen-ws.hex"
$exe = Join-Path $stage "listen-ws.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
& dotnet exec $VireDll --compiler compile-native.vire data/native-listen-ws/listen-ws.vire data/native-listen-ws/listen-ws.hex pe
if ($LASTEXITCODE -ne 0) { throw "compile exit $LASTEXITCODE" }
$h = [System.IO.File]::ReadAllText($hex).Trim()
$bytes = New-Object byte[] ($h.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }
[System.IO.File]::WriteAllBytes($exe, $bytes)
$pe = [System.IO.File]::ReadAllBytes($exe)
if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "missing MZ" }
$ascii = [Text.Encoding]::ASCII.GetString($pe)
if ($ascii -notmatch " Forbidden") { throw "PE missing Forbidden phrase" }
Write-Host "pe_mz_ok forbidden_phrase_ok"

$OnWindows = ($env:OS -eq "Windows_NT")
if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { if ($IsWindows) { $OnWindows = $true } }
if (-not $OnWindows) {
    Write-Host "pe_execute_skipped linux agent cannot run PE"
    Write-Host ("PASS_AFTER compile-only at " + $AfterSha)
    exit 0
}

Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
public static class VireListenWsFix {
    const string Guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    public static TcpListener Listen(out int port) {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        port = ((IPEndPoint)l.LocalEndpoint).Port;
        Thread t = new Thread(() => {
            try {
                while (true) {
                    TcpClient c = l.AcceptTcpClient();
                    Thread inner = new Thread(() => Serve(c));
                    inner.IsBackground = true;
                    inner.Start();
                }
            } catch { }
        });
        t.IsBackground = true;
        t.Start();
        return l;
    }
    static void Serve(TcpClient c) {
        try {
            using (c) {
                NetworkStream s = c.GetStream();
                s.ReadTimeout = 5000;
                byte[] buf = new byte[16384];
                int n = s.Read(buf, 0, buf.Length);
                string text = Encoding.ASCII.GetString(buf, 0, n);
                if (text.Contains("/ws/refuse")) {
                    byte[] body = Encoding.ASCII.GetBytes("forbidden");
                    byte[] resp = Encoding.ASCII.GetBytes("HTTP/1.1 403 Forbidden\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
                    s.Write(resp, 0, resp.Length);
                    s.Write(body, 0, body.Length);
                    return;
                }
                if (!text.Contains("Upgrade: websocket")) {
                    byte[] bad = Encoding.ASCII.GetBytes("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    s.Write(bad, 0, bad.Length);
                    return;
                }
                string key = "";
                foreach (string line in text.Split(new string[] { "\r\n" }, StringSplitOptions.None)) {
                    if (line.StartsWith("Sec-WebSocket-Key:", StringComparison.OrdinalIgnoreCase))
                        key = line.Substring(18).Trim();
                }
                byte[] acc;
                using (SHA1 sha = SHA1.Create()) {
                    acc = sha.ComputeHash(Encoding.ASCII.GetBytes(key + Guid));
                }
                string accept = Convert.ToBase64String(acc);
                byte[] ok = Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n");
                s.Write(ok, 0, ok.Length);
            }
        } catch { }
    }
}
"@

$upPort = 0
$listener = [VireListenWsFix]::Listen([ref]$upPort)
Write-Host "upstream 127.0.0.1:$upPort"

function Probe([int]$Port, [string]$Req) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout = 5000
    $tcp.Connect("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $bytes = [Text.Encoding]::ASCII.GetBytes($Req)
    $stream.Write($bytes, 0, $bytes.Length)
    $buf = New-Object byte[] 4096
    $n = $stream.Read($buf, 0, $buf.Length)
    $tcp.Close()
    return [Text.Encoding]::ASCII.GetString($buf, 0, $n)
}

function Transcript([int]$Port) {
    $bad = Probe $Port "GET /ws/echo HTTP/1.1`r`nHost: 127.0.0.1`r`nUpgrade: h2c`r`nConnection: Upgrade`r`n`r`n"
    $ref = Probe $Port "GET /ws/refuse HTTP/1.1`r`nHost: 127.0.0.1`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n"
    $ok = Probe $Port "GET /ws/echo HTTP/1.1`r`nHost: 127.0.0.1`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n"
    if ($ok -notmatch "101 Switching Protocols") { throw "echo missing 101: $ok" }
    if ($ok -notmatch "s3pPLMBiTxaQ9kYGzzhZRbK\+xOo=") { throw "echo missing accept" }
    if ($bad -notmatch "400") { throw "h2c expected 400: $bad" }
    if ($ref -notmatch "403 Forbidden") { throw "refuse expected 403 Forbidden: $ref" }
    if ($ref -match "101") { throw "refuse opened: $ref" }
    return "bad=$bad`nref=$ref`nok=$ok"
}

$hostProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-listen-ws/listen-ws.vire", "$upPort") -WorkingDirectory $Root
$hport = Get-ListenPort $hostProc
$hostT = Transcript $hport
$hostProc.Kill()

$natProc = Start-VireProcess -FilePath $exe -ArgumentList @("$upPort") -WorkingDirectory $Root
$nport = Get-ListenPort $natProc
$natT = Transcript $nport
$natProc.Kill()
try { $listener.Stop() } catch { }

if ($hostT -ne $natT) { throw "HOST_NATIVE_MISMATCH" }
Write-Host "HOST_NATIVE_MATCH listen-ws"
Write-Host ("PASS_AFTER at " + $AfterSha)
exit 0
