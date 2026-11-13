# Fail-before / pass-after: guest WebSocket server on loopback. No TLS.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$BaseSha = "5b10ea5fa5eea46859f17a52b36037d9d088c01d"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $leaf = [IO.Path]::GetFileName($Args[0])
    $savedBudget = $env:VIRE_BUDGET
    if ($leaf -eq "compile-native.vire" -or $leaf -eq "compiler.vire") {
        $Args = @("--compiler") + $Args
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    }
    try {
        $out = & dotnet exec $VireDll @Args
        $code = $LASTEXITCODE
        if ($null -ne $out) { $out | Write-Host }
        if ($null -eq $code) { return 0 }
        return [int]$code
    } finally {
        if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
    }
}

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --depth 1 origin $BaseSha
}
$oldLines = @(& git -C $Root show "${BaseSha}:compile-native.vire")
$oldNative = ($oldLines | ForEach-Object { $_ }) -join "`n"
if ($oldNative -match 'nm == "ws_listen"') { throw "base compile-native already has ws_listen" }
if ($oldNative -notmatch 'define main') { throw "fail-before snapshot missing define main" }
$oldSrc = Join-Path $Root "compile-native-fail-before.vire"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($oldSrc, $oldNative + "`n", $utf8)
Set-Content -Path (Join-Path $Data "ws-fail-before.vire") -Value "define main`n  ws_listen with 0`nend`n"
$probeHex = Join-Path $Data "ws-fail-before.hex"
if (Test-Path $probeHex) { Remove-Item -Force $probeHex }
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
try {
    $beforeOut = & dotnet exec $VireDll --compiler "compile-native-fail-before.vire" "data/ws-fail-before.vire" "data/ws-fail-before.hex" 2>&1 | Out-String
    $beforeCode = $LASTEXITCODE
} finally {
    if (Test-Path $oldSrc) { Remove-Item -Force $oldSrc }
}
$env:VIRE_BUDGET = "5000000"
Write-Output $beforeOut.TrimEnd()
Write-Output "fail_before_compile_exit $beforeCode"
if ($beforeCode -eq 0) { throw "fail-before compile unexpectedly succeeded" }
if ($beforeOut -notmatch "there is no definition named ws_listen") {
    throw "fail-before missing unavailable ws_listen"
}
Write-Output "FAIL_BEFORE at $BaseSha showing ws_listen is unavailable"

$lib1 = Get-Content -Raw (Join-Path $Root "src/rt-sha1.vire")
$proto = Get-Content -Raw (Join-Path $Root "src/rt-ws-proto.vire")
$proto = $proto -replace '(?m)^use "src/rt-sha1.vire"\s*', ''
$prove = Get-Content -Raw (Join-Path $Root "tests/native/ws-prove.vire")
$prove = $prove -replace '(?m)^use "src/rt-sha1.vire"\s*', ''
$prove = $prove -replace '(?m)^use "src/rt-ws-proto.vire"\s*', ''
$prove = $prove -replace '(?m)^use "src/rt-ws.vire"\s*', ''
Set-Content -Path (Join-Path $Data "ws-prove.vire") -Value ($lib1 + "`n" + $proto + "`n" + $prove) -NoNewline

Write-Output "ws_host_prove_start"
$hostProve = & dotnet exec $VireDll (Join-Path $Data "ws-prove.vire")
$hostProveCode = $LASTEXITCODE
Write-Output $hostProve
Write-Output "ws_host_prove_exit $hostProveCode"
if ($hostProveCode -ne 0) { throw "host ws-prove exit $hostProveCode" }
if ("$hostProve" -notmatch "WS PROVE pass") { throw "host ws-prove missing pass" }
if ("$hostProve" -notmatch "s3pPLMBiTxaQ9kYGzzhZRbK\+xOo=") { throw "host missing RFC 6455 accept" }
$hexRel = "data/ws-prove.hex"
if (Test-Path (Join-Path $Root $hexRel)) { Remove-Item -Force (Join-Path $Root $hexRel) }
$compileCode = Invoke-Vire compile-native.vire "data/ws-prove.vire" $hexRel
if ($compileCode -ne 0) { throw "compile-native ws-prove exit $compileCode" }
$exe = Join-Path $Data "ws-prove.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$peProve = & $exe
$peProveCode = $LASTEXITCODE
Write-Output $peProve
Write-Output "ws_pe_prove_exit $peProveCode"
if ($peProveCode -ne 0) { throw "PE ws-prove exit $peProveCode" }
$hostNorm = (($hostProve | Out-String) -replace '\r', '').Trim()
$peNorm = (($peProve | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE ws-prove stdout differ"
}
Write-Output "ws host pe prove match"

function Start-WsGuest([string]$FilePath, [string[]]$ArgumentList) {
    $outFile = Join-Path $Data "ws-echo.out.txt"
    $errFile = Join-Path $Data "ws-echo.err.txt"
    if (Test-Path $outFile) { Remove-Item -Force $outFile }
    if (Test-Path $errFile) { Remove-Item -Force $errFile }
    $start = @{
        FilePath = $FilePath
        WorkingDirectory = $Root
        NoNewWindow = $true
        PassThru = $true
        RedirectStandardOutput = $outFile
        RedirectStandardError = $errFile
    }
    if ($ArgumentList -and $ArgumentList.Count -gt 0) { $start.ArgumentList = $ArgumentList }
    $p = Start-Process @start
    $port = $null
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $outFile) {
            $txt = Get-Content -Raw $outFile -ErrorAction SilentlyContinue
            if ($txt -match "listening on 127\.0\.0\.1:(\d+)") {
                $port = [int]$Matches[1]
                break
            }
        }
        if ($p.HasExited) { break }
        Start-Sleep -Milliseconds 100
    }
    return @{ Proc = $p; Port = $port; OutFile = $outFile; ErrFile = $errFile }
}

function Invoke-WsEcho([int]$Port) {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $uri = [Uri]"ws://127.0.0.1:$Port/ws/kick"
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter(10000)
    $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
    $send = [System.Text.Encoding]::UTF8.GetBytes("ping")
    $seg = [ArraySegment[byte]]$send
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
    $buf = New-Object byte[] 256
    $recvSeg = [ArraySegment[byte]]$buf
    $got = $ws.ReceiveAsync($recvSeg, $cts.Token).GetAwaiter().GetResult()
    $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $got.Count)
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "bye", $cts.Token).GetAwaiter().GetResult()
    $ws.Dispose()
    if ($text -ne "ping") { throw "echo mismatch '$text'" }
    return $text
}

function Invoke-WsAdversary([int]$Port) {
    function Send-Raw([byte[]]$bytes) {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port)
        $s = $c.GetStream()
        $s.Write($bytes, 0, $bytes.Length)
        $s.ReadTimeout = 2000
        $buf = New-Object byte[] 256
        try { [void]$s.Read($buf, 0, $buf.Length) } catch { }
        $c.Close()
    }
    $badKey = [Text.Encoding]::ASCII.GetBytes("GET /ws/kick HTTP/1.1`r`nHost: 127.0.0.1`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Version: 13`r`nSec-WebSocket-Key: %%%`r`n`r`n")
    Send-Raw $badKey
    $ok = [Text.Encoding]::ASCII.GetBytes("GET /ws/kick HTTP/1.1`r`nHost: 127.0.0.1`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Version: 13`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`n`r`n")
    $unmasked = [byte[]](0x81, 0x01, 0x61)
    $oversize = [byte[]](0x81, 0xFF, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
    $len64 = [byte[]](0x81, 0xFF, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0)
    $fragCtl = [byte[]](0x08, 0x81, 1, 2, 3, 4, 0)
    $badUtf = [byte[]](0x81, 0x81, 0, 0, 0, 0, 0x80)
    foreach ($frame in @($unmasked, $oversize, $len64, $fragCtl, $badUtf)) {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port)
        $s = $c.GetStream()
        $s.Write($ok, 0, $ok.Length)
        $hdr = New-Object byte[] 512
        $s.ReadTimeout = 3000
        try { [void]$s.Read($hdr, 0, $hdr.Length) } catch { }
        $s.Write($frame, 0, $frame.Length)
        try { [void]$s.Read($hdr, 0, $hdr.Length) } catch { }
        $c.Close()
    }
}

Copy-Item (Join-Path $Root "tests/native/ws-echo.vire") (Join-Path $Data "ws-echo.vire") -Force
Write-Output "ws_host_echo_start"
$hostEcho = Start-WsGuest "dotnet" @("exec", $VireDll, "data/ws-echo.vire")
if (-not $hostEcho.Port) {
    if ($hostEcho.Proc -and -not $hostEcho.Proc.HasExited) { try { $hostEcho.Proc.Kill($true) } catch { } }
    throw "host ws-echo did not print listening port"
}
Write-Output "ws_host_listen 127.0.0.1:$($hostEcho.Port)"
$echoed = Invoke-WsEcho $hostEcho.Port
Write-Output "ws_host_echo $echoed"
Invoke-WsAdversary $hostEcho.Port
Write-Output "ws_host_adversary ok"
if (-not $hostEcho.Proc.HasExited) { try { $hostEcho.Proc.Kill($true) } catch { } }

$echoHex = "data/ws-echo.hex"
if (Test-Path (Join-Path $Root $echoHex)) { Remove-Item -Force (Join-Path $Root $echoHex) }
$compileEcho = Invoke-Vire compile-native.vire "data/ws-echo.vire" $echoHex
if ($compileEcho -ne 0) { throw "compile-native ws-echo exit $compileEcho" }
$echoExe = Join-Path $Data "ws-echo.exe"
Convert-HexToExe (Join-Path $Root $echoHex) $echoExe
try { Unblock-File -Path $echoExe } catch { }
Write-Output "ws_pe_echo_start"
$peEcho = Start-WsGuest $echoExe @()
if (-not $peEcho.Port) {
    if ($peEcho.Proc -and -not $peEcho.Proc.HasExited) { try { $peEcho.Proc.Kill($true) } catch { } }
    $err = if (Test-Path $peEcho.ErrFile) { Get-Content -Raw $peEcho.ErrFile } else { "" }
    $out = if (Test-Path $peEcho.OutFile) { Get-Content -Raw $peEcho.OutFile } else { "" }
    throw "PE ws-echo did not print listening port out=$out err=$err"
}
Write-Output "ws_pe_listen 127.0.0.1:$($peEcho.Port)"
$peEchoed = Invoke-WsEcho $peEcho.Port
Write-Output "ws_pe_echo $peEchoed"
Invoke-WsAdversary $peEcho.Port
Write-Output "ws_pe_adversary ok"
if (-not $peEcho.Proc.HasExited) { try { $peEcho.Proc.Kill($true) } catch { } }

Write-Output "PASS_AFTER at $AfterSha host and gen1 PE websocket echo on loopback"
Write-Output "native ws windows ok"
