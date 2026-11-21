# CouchStation Windows PE: refused WebSocket upgrade must never be 101.
# This Linux agent cannot execute PE. Do not claim PE proof from this run.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "a64cfe5fdb398ac7c8049bd41ac431d780a0b09e"
Write-Host ("FAIL_BEFORE at " + $FailBefore + ": native listen 101d GET /ws/refuse")
Write-Host ("PASS_AFTER expect " + $AfterSha)

$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
$ws = Get-Content -Raw (Join-Path $Root "src\rt-ws.vire")
if ($ws -match 'pin with labels, "rt_listen", image') { throw "rt_listen still overwritten by emitWsListen" }
$listen = Get-Content -Raw (Join-Path $Root "VireListen.cs")
if ($listen -match 'headers.Path != "/ws/refuse"') { throw "path guard must not mask refusal" }
if ($listen -notmatch "wsIntent == 1 && code == 101") { throw "101 must require route status" }
Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000"
Write-Host "property: refused upgrade never 101 (host=PE)"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
$stage = Join-Path $Root "data/native-ws-refuse"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Root "tests/rebuild/guests/listen-ws.vire") (Join-Path $stage "listen-ws.vire") -Force
$hex = Join-Path $stage "listen-ws.hex"
$exe = Join-Path $stage "listen-ws.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
& dotnet exec $VireDll --compiler compile-native.vire data/native-ws-refuse/listen-ws.vire data/native-ws-refuse/listen-ws.hex pe
if ($LASTEXITCODE -ne 0) { throw "compile exit $LASTEXITCODE" }
$h = [System.IO.File]::ReadAllText($hex).Trim()
$bytes = New-Object byte[] ($h.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }
[System.IO.File]::WriteAllBytes($exe, $bytes)
$pe = [System.IO.File]::ReadAllBytes($exe)
if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "missing MZ" }
Write-Host "pe_mz_ok"

function Get-ListenPort([System.Diagnostics.Process]$proc) {
    $deadline = (Get-Date).AddSeconds(12)
    $buf = ""
    while ((Get-Date) -lt $deadline) {
        $line = $proc.StandardOutput.ReadLine()
        if ($null -eq $line) { break }
        $buf += $line
        if ($line -match "listening on 127.0.0.1:(\d+)") { return [int]$Matches[1] }
    }
    throw "no listen port: $buf"
}

function Probe-Refuse([int]$Port) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout = 5000
    $tcp.Connect("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $req = [Text.Encoding]::ASCII.GetBytes("GET /ws/refuse HTTP/1.1`r`nHost: 127.0.0.1`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n")
    $stream.Write($req, 0, $req.Length)
    $buf = New-Object byte[] 4096
    $n = $stream.Read($buf, 0, $buf.Length)
    $tcp.Close()
    $text = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
    $line = ($text -split "`r`n")[0]
    if ($line -match "101" -or $text -match "Switching Protocols") { throw "OPEN: $line" }
    if ($line -notmatch "403") { throw "expected 403 got $line" }
    return $line
}

$psiH = New-Object System.Diagnostics.ProcessStartInfo
$psiH.FileName = "dotnet"
$psiH.Arguments = "exec `"$VireDll`" data/native-ws-refuse/listen-ws.vire 18080"
$psiH.WorkingDirectory = $Root
$psiH.RedirectStandardOutput = $true
$psiH.UseShellExecute = $false
$hostProc = [System.Diagnostics.Process]::Start($psiH)
$hport = Get-ListenPort $hostProc
$hostLine = Probe-Refuse $hport
$hostProc.Kill()

$psiN = New-Object System.Diagnostics.ProcessStartInfo
$psiN.FileName = $exe
$psiN.Arguments = "18080"
$psiN.WorkingDirectory = $Root
$psiN.RedirectStandardOutput = $true
$psiN.UseShellExecute = $false
$natProc = [System.Diagnostics.Process]::Start($psiN)
$nport = Get-ListenPort $natProc
$natLine = Probe-Refuse $nport
$natProc.Kill()

Write-Host "host $hostLine"
Write-Host "native $natLine"
if ($hostLine -ne $natLine) { throw "HOST_NATIVE_MISMATCH" }
Write-Host "HOST_NATIVE_MATCH refuse 403"
Write-Host ("PASS_AFTER at " + $AfterSha)
exit 0
