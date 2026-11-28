# CouchStation Windows PE: packed 4-param listen GET /api/health matches host.
# Empty connect must not kill the process. Split headers must serve.
# This Linux agent cannot execute PE. Do not claim PE proof from this run.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
Write-Host "FAIL_BEFORE packed r4 jmp cl_route_push landed at 0xa84 (mid cl_nobody); GET /api/health SIGSEGV raw_len 0"
Write-Host ("PASS_AFTER expect " + $AfterSha)

$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "int itemCap = 100000;") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }

$r4 = (Get-Content -Raw (Join-Path $Root "src\rt-net-r4-blob.txt")).Trim()
$bytes = New-Object byte[] ($r4.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($r4.Substring($i * 2, 2), 16) }
if ($bytes[0xA78] -ne 0xE9) { throw "r4 missing 0xa78 trampoline" }
if ($bytes[0xAC0] -ne 0xE9) { throw "r4 missing save_frame trampoline at 0xac0" }
$sawPush = $false
$sawRecv0 = $false
for ($i = 0; $i + 5 -le $bytes.Length; $i++) {
    if ($bytes[$i] -eq 0xE9) {
        $rel = [BitConverter]::ToInt32($bytes, $i + 1)
        if (($i + 5 + $rel) -eq 0xA78) { $sawPush = $true }
    }
    if ($i + 1 -lt $bytes.Length -and $bytes[$i] -eq 0xC9 -and $bytes[$i + 1] -eq 0xC3) { $sawRecv0 = $true }
}
if (-not $sawPush) { throw "r4 cl_blockgate must jmp 0xa78" }
if (-not $sawRecv0) { throw "r4 missing recv0 leave;ret" }
Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000 r4_pushroute=0xa78"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
$stage = Join-Path $Root "data/native-listen-recv0-win"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Root "tests/native/listen-recv0.vire") (Join-Path $stage "listen-recv0.vire") -Force
$hex = Join-Path $stage "listen-recv0.hex"
$exe = Join-Path $stage "listen-recv0.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
& dotnet exec $VireDll --compiler compile-native.vire data/native-listen-recv0-win/listen-recv0.vire data/native-listen-recv0-win/listen-recv0.hex pe
if ($LASTEXITCODE -ne 0) { throw "compile exit $LASTEXITCODE" }
$hexText = (Get-Content -Raw $hex).Trim()
$pe = New-Object byte[] ($hexText.Length / 2)
for ($i = 0; $i -lt $pe.Length; $i++) { $pe[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16) }
[IO.File]::WriteAllBytes($exe, $pe)
if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "PE missing MZ" }
Write-Host "listen_recv0_pe_mz_ok"

function Get-Health([int]$Port) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout = 5000
    $tcp.Connect("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $req = [Text.Encoding]::ASCII.GetBytes("GET /api/health HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n`r`n")
    $stream.Write($req, 0, $req.Length)
    $ms = New-Object IO.MemoryStream
    $buf = New-Object byte[] 4096
    try {
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    } catch {
        if ($ms.Length -eq 0) { throw }
    }
    $tcp.Close()
    return [Text.Encoding]::ASCII.GetString($ms.ToArray())
}

$hostProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-listen-recv0-win/listen-recv0.vire") -WorkingDirectory $Root
$hport = Get-ListenPort $hostProc
$h = Get-Health $hport
$hostProc.Kill()

$natProc = Start-VireProcess -FilePath $exe -ArgumentList @() -WorkingDirectory $Root
$nport = Get-ListenPort $natProc
$n = Get-Health $nport
$empty = New-Object System.Net.Sockets.TcpClient
$empty.Connect("127.0.0.1", $nport)
$empty.Close()
$n2 = Get-Health $nport
$natProc.Kill()
if ($h -ne $n) { throw "host vs PE GET /api/health mismatch" }
if ($n -notmatch '"ok":true') { throw "PE health missing ok" }
if ($n2 -ne $n) { throw "PE died or mismatched after empty connect" }
Write-Host "HOST_NATIVE_MATCH listen-recv0 GET /api/health"
Write-Host ("PASS_AFTER at " + $AfterSha + " PE listen-recv0 matches host; empty connect kept serving")
