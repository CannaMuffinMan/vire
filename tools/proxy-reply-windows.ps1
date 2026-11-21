# CouchStation Windows PE: listen + proxy_reply must match host (not empty HTTP).
# This Linux agent cannot execute PE. Do not claim PE proof from this run.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "962be3ac7b8c9979579a9531f11cb2356d141814"
Write-Host ("FAIL_BEFORE at " + $FailBefore + ": native listen GET /proxy empty HTTP (SEGV rdx=1)")
Write-Host ("PASS_AFTER expect " + $AfterSha)

$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
$blob = (Get-Content -Raw (Join-Path $Root "src\rt-net-blob.txt")).Trim()
if ($blob.Substring(2728 * 2, 6) -ne "488d15") { throw "packed GET body park missing lea txt_empty" }
$fixes = Get-Content -Raw (Join-Path $Root "src\rt-net-fixes.txt")
if ($fixes -notmatch "ab0a0000a400") { throw "txt_empty reloc at blob+2731 missing" }
Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
$stage = Join-Path $Root "data/native-proxy-reply"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Root "tests/native/proxy-reply.vire") (Join-Path $stage "proxy-reply.vire") -Force
Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $stage "http-client.vire") -Force
$hex = Join-Path $stage "proxy-reply.hex"
$exe = Join-Path $stage "proxy-reply.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
& dotnet exec $VireDll --compiler compile-native.vire data/native-proxy-reply/proxy-reply.vire data/native-proxy-reply/proxy-reply.hex pe
if ($LASTEXITCODE -ne 0) { throw "compile exit $LASTEXITCODE" }
$hexText = (Get-Content -Raw $hex).Trim()
$pe = New-Object byte[] ($hexText.Length / 2)
for ($i = 0; $i -lt $pe.Length; $i++) {
    $pe[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16)
}
[IO.File]::WriteAllBytes($exe, $pe)
if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "PE missing MZ" }
$ascii = [Text.Encoding]::ASCII.GetString($pe)
if ($ascii -notmatch "ws2_32") { throw "PE missing ws2_32" }
Write-Host "proxy_reply_pe_mz_ok ws2_32_ok"

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse("127.0.0.1"), 0)
$listener.Start()
$upPort = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
Write-Host ("upstream 127.0.0.1:" + $upPort)
$script:ProxyReplyListener = $listener
$upThread = New-Object System.Threading.Thread ([System.Threading.ThreadStart]{
    $lis = $script:ProxyReplyListener
    while ($true) {
        try {
            $c = $lis.AcceptTcpClient()
            $ns = $c.GetStream()
            $buf = New-Object byte[] 4096
            [void]$ns.Read($buf, 0, $buf.Length)
            $payload = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/plain`r`nContent-Length: 5`r`n`r`nup-ok")
            $ns.Write($payload, 0, $payload.Length)
            $c.Close()
        } catch { break }
    }
})
$upThread.IsBackground = $true
$upThread.Start()

function Get-Proxy([int]$Port) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout = 5000
    $tcp.Connect("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $req = [Text.Encoding]::ASCII.GetBytes("GET /proxy HTTP/1.1`r`nHost: x`r`nConnection: close`r`n`r`n")
    $stream.Write($req, 0, $req.Length)
    $ms = New-Object IO.MemoryStream
    $buf = New-Object byte[] 4096
    try {
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    } catch { }
    $tcp.Close()
    return [Text.Encoding]::ASCII.GetString($ms.ToArray())
}

$hostProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-proxy-reply/proxy-reply.vire", "$upPort") -WorkingDirectory $Root
$hport = Get-ListenPort $hostProc
$h = Get-Proxy $hport
$hostProc.Kill()

$natProc = Start-VireProcess -FilePath $exe -ArgumentList @("$upPort") -WorkingDirectory $Root
$nport = Get-ListenPort $natProc
$p = Get-Proxy $nport
$natProc.Kill()
$listener.Stop()

Write-Host ("host_raw " + $h.Substring(0, [Math]::Min(180, $h.Length)))
Write-Host ("pe_raw " + $p.Substring(0, [Math]::Min(180, $p.Length)))
if ($h -notmatch "up-ok") { throw "host missing up-ok" }
if ($p -notmatch "up-ok") { throw "PE empty or missing up-ok" }
if (($h -split " ")[1] -ne ($p -split " ")[1]) { throw "status mismatch" }
Write-Host ("PASS_AFTER at " + $AfterSha + " host=PE GET /proxy")
Write-Host "proxy-reply-windows ok"
exit 0
