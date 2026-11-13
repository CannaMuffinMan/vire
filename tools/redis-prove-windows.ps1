# Fail-before / pass-after: guest RESP2 Redis client on loopback TCP (#64).
# Caps unchanged. No TLS. Windows Defender untouched.
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
Write-VireHostInfo

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

function Inline-Guest([string]$SrcName, [string]$DestRel) {
    $lib = Get-Content -Raw (Join-Path $Root "src/rt-redis.vire")
    $prove = Get-Content -Raw (Join-Path $Root $SrcName)
    $prove = $prove -replace '(?m)^use "src/rt-redis.vire"\s*', ''
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $Root $DestRel), $lib + "`n" + $prove, $utf8)
}

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --depth 1 origin $BaseSha
}
$missing = $true
git cat-file -e "${BaseSha}:src/rt-redis.vire" 2>$null
if ($LASTEXITCODE -eq 0) { $missing = $false }
if (-not $missing) { throw "fail-before $BaseSha already has src/rt-redis.vire" }
Write-Output "FAIL_BEFORE at $BaseSha (no client)"

$beforeGuest = Join-Path $Data "redis-fail-before.vire"
Set-Content -Path $beforeGuest -Value "define main`n  redis_ping with 1`nend`n"
$beforeOut = & dotnet exec $VireDll "data/redis-fail-before.vire" 2>&1 | Out-String
$beforeCode = $LASTEXITCODE
Write-Output $beforeOut.TrimEnd()
Write-Output "fail_before_exit $beforeCode"
if ($beforeCode -eq 0) { throw "fail-before redis_ping unexpectedly succeeded" }
if ($beforeOut -notmatch "there is no definition named redis_ping") {
    throw "fail-before missing unavailable redis_ping"
}
Write-Output "FAIL_BEFORE at $BaseSha showing redis_ping is unavailable"

Write-Output "redis_decode_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostDecode = & dotnet exec $VireDll redis-decode-prove.vire
$hostDecodeCode = $LASTEXITCODE
$sw.Stop()
Write-Output $hostDecode
Write-Output "redis_decode_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "redis_decode_host_exit $hostDecodeCode"
if ($hostDecodeCode -ne 0) { throw "host redis-decode-prove exit $hostDecodeCode" }
if ("$hostDecode" -notmatch "REDIS DECODE PROVE pass") { throw "host decode missing pass" }
if ("$hostDecode" -notmatch "ADV oversize bulk REJECT") { throw "missing oversize bulk reject" }
if ("$hostDecode" -notmatch "ADV truncated REJECT") { throw "missing truncated reject" }
if ("$hostDecode" -notmatch "ADV bad CRLF REJECT") { throw "missing bad CRLF reject" }
if ("$hostDecode" -notmatch "ADV too-deep REJECT") { throw "missing too-deep reject" }
Write-Output "PASS_AFTER host redis-decode-prove"

Inline-Guest "redis-decode-prove.vire" "data/redis-decode-prove.vire"
$decodeHexRel = "data/redis-decode-prove.hex"
if (Test-Path (Join-Path $Root $decodeHexRel)) { Remove-Item -Force (Join-Path $Root $decodeHexRel) }
$compileDecode = Invoke-Vire compile-native.vire "data/redis-decode-prove.vire" $decodeHexRel
if ($compileDecode -ne 0) { throw "compile-native redis-decode exit $compileDecode" }
$decodeExe = Join-Path $Data "redis-decode-prove.exe"
Convert-HexToExe (Join-Path $Root $decodeHexRel) $decodeExe
try { Unblock-File -Path $decodeExe } catch { }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peDecode = & $decodeExe
$peDecodeCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peDecode
Write-Output "redis_decode_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "redis_decode_pe_exit $peDecodeCode"
if ($peDecodeCode -ne 0) { throw "redis decode PE exit $peDecodeCode" }
$hostNorm = (($hostDecode | Out-String) -replace '\r', '').Trim()
$peNorm = (($peDecode | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH decode"
    throw "host interpreter and gen1 PE decode stdout differ"
}
Write-Output "PASS_AFTER host and gen1 PE redis decode stdout identical"

Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public class VireRedisAdv {
    public TcpListener Listener;
    Thread worker;
    volatile bool stop;
    int n;
    public int Start() {
        Listener = new TcpListener(IPAddress.Parse("127.0.0.1"), 0);
        Listener.Start();
        worker = new Thread(Run);
        worker.IsBackground = true;
        worker.Start();
        return ((IPEndPoint)Listener.LocalEndpoint).Port;
    }
    static void Drain(NetworkStream stream) {
        stream.ReadTimeout = 500;
        byte[] buf = new byte[256];
        try { stream.Read(buf, 0, buf.Length); } catch (Exception) { }
    }
    void Run() {
        try {
            while (!stop) {
                TcpClient client = Listener.AcceptTcpClient();
                try {
                    NetworkStream stream = client.GetStream();
                    Drain(stream);
                    int k = System.Threading.Interlocked.Increment(ref n);
                    byte[] payload;
                    if (k == 1) payload = Encoding.ASCII.GetBytes("\u0024999999999\r\n");
                    else if (k == 2) payload = Encoding.ASCII.GetBytes("\u00245\r\nfoo");
                    else if (k == 3) payload = Encoding.ASCII.GetBytes("\u00243\r\nfoo\n");
                    else {
                        StringBuilder deep = new StringBuilder();
                        for (int i = 0; i < 20; i++) deep.Append("*1\r\n");
                        deep.Append("+x\r\n");
                        payload = Encoding.ASCII.GetBytes(deep.ToString());
                    }
                    stream.Write(payload, 0, payload.Length);
                } finally { client.Close(); }
            }
        } catch (SocketException) { }
        catch (ObjectDisposedException) { }
    }
    public void Halt() {
        stop = true;
        try { Listener.Stop(); } catch (Exception) { }
    }
}
"@
$advFix = New-Object VireRedisAdv
$advPort = $advFix.Start()
Write-Output "adv_listen 127.0.0.1:$advPort"
$advPortText = [string]$advPort

Write-Output "redis_adv_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostAdv = & dotnet exec $VireDll redis-adv-prove.vire $advPortText
$hostAdvCode = $LASTEXITCODE
$sw.Stop()
Write-Output $hostAdv
Write-Output "redis_adv_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "redis_adv_host_exit $hostAdvCode"
if ($hostAdvCode -ne 0) { throw "host redis-adv-prove exit $hostAdvCode" }
if ("$hostAdv" -notmatch "REDIS ADV PROVE pass") { throw "host adv missing pass" }

Inline-Guest "redis-adv-prove.vire" "data/redis-adv-prove.vire"
$advHexRel = "data/redis-adv-prove.hex"
if (Test-Path (Join-Path $Root $advHexRel)) { Remove-Item -Force (Join-Path $Root $advHexRel) }
$compileAdv = Invoke-Vire compile-native.vire "data/redis-adv-prove.vire" $advHexRel
if ($compileAdv -ne 0) { throw "compile-native redis-adv exit $compileAdv" }
$advExe = Join-Path $Data "redis-adv-prove.exe"
Convert-HexToExe (Join-Path $Root $advHexRel) $advExe
try { Unblock-File -Path $advExe } catch { }
try { $advFix.Halt() } catch { }
$advFix = New-Object VireRedisAdv
$advPort = $advFix.Start()
$advPortText = [string]$advPort
Write-Output "adv_listen_pe 127.0.0.1:$advPort"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peAdv = & $advExe $advPortText
$peAdvCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peAdv
Write-Output "redis_adv_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "redis_adv_pe_exit $peAdvCode"
if ($peAdvCode -ne 0) { throw "redis adv PE exit $peAdvCode" }
$hostAdvNorm = (($hostAdv | Out-String) -replace '\r', '').Trim()
$peAdvNorm = (($peAdv | Out-String) -replace '\r', '').Trim()
if ($hostAdvNorm -ne $peAdvNorm) {
    Write-Output "HOST_PE_MISMATCH adv"
    throw "host interpreter and gen1 PE adv stdout differ"
}
Write-Output "PASS_AFTER host and gen1 PE adversarial stdout identical"
try { $advFix.Halt() } catch { }

function Start-RedisWindows {
    $bind = "127.0.0.1"
    $port = 16379
    $server = $null
    $zip = Join-Path $Data "redis-win.zip"
    $dir = Join-Path $Data "redis-win"
    $urls = @(
        "https://github.com/tporadowski/redis/releases/download/v5.0.14.1/Redis-x64-192.168.1.1.zip",
        "https://github.com/microsoftarchive/redis/releases/download/win-3.0.504/Redis-x64-3.0.504.zip"
    )
    foreach ($url in $urls) {
        try {
            Write-Output "redis_download $url"
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
            Expand-Archive -Path $zip -DestinationPath $dir -Force
            $server = Get-ChildItem -Path $dir -Recurse -Filter "redis-server.exe" | Select-Object -First 1
            if ($null -ne $server) { break }
        } catch {
            Write-Output ("redis_download_fail " + $_.Exception.Message)
        }
    }
    if ($null -eq $server) {
        $choco = Get-Command choco -ErrorAction SilentlyContinue
        if ($choco) {
            try {
                & choco install redis-64 -y --no-progress
                $server = Get-ChildItem -Path "C:\Program Files\Redis" -Filter "redis-server.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            } catch {
                Write-Output ("choco_redis_fail " + $_.Exception.Message)
            }
        }
    }
    if ($null -eq $server) { return $null }
    Write-Output ("redis_server_exe " + $server.FullName)
    $proc = Start-Process -FilePath $server.FullName -ArgumentList @(
        "--port", "$port", "--bind", $bind
    ) -WorkingDirectory $server.DirectoryName -PassThru -WindowStyle Hidden
    $ok = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $c.Connect($bind, $port)
            $c.Close()
            $ok = $true
            break
        } catch { }
    }
    if (-not $ok) {
        try { Stop-Process -Id $proc.Id -Force } catch { }
        return $null
    }
    Write-Output "redis_listen ${bind}:$port"
    return @{ Port = $port; Proc = $proc }
}

$redis = Start-RedisWindows
if ($null -eq $redis) {
    Write-Output "REDIS_SERVER_UNAVAILABLE on this Windows runner (no redis-server.exe / Memurai). Decode and adversarial fake-server proofs still ran. Live SET/GET against a real Redis binary was not executed here."
    Write-Output "gen1_hello_and_gen2_sha covered by job native-selfhost-windows on this PR"
    Write-Output "redis windows prove ok (decode+adv; live redis residual)"
    exit 0
}

try {
    $livePortText = [string]$redis.Port
    Write-Output "redis_live_host_start"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $hostLive = & dotnet exec $VireDll redis-live-prove.vire $livePortText
    $hostLiveCode = $LASTEXITCODE
    $sw.Stop()
    Write-Output $hostLive
    Write-Output "redis_live_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
    Write-Output "redis_live_host_exit $hostLiveCode"
    if ($hostLiveCode -ne 0) { throw "host redis-live-prove exit $hostLiveCode" }
    $hostLiveNorm = (($hostLive | Out-String) -replace '\r', '').Trim()
    if ($hostLiveNorm -notmatch "REDIS LIVE PROVE pass") { throw "host live missing pass" }
    if ($hostLiveNorm -notmatch "(?m)^PING PONG$") { throw "host missing PING PONG" }
    if ($hostLiveNorm -notmatch "(?m)^SET OK$") { throw "host missing SET OK" }
    if ($hostLiveNorm -notmatch "(?m)^GET hello$") { throw "host missing GET hello" }
    if ($hostLiveNorm -notmatch "(?m)^INCR 1$") { throw "host missing INCR 1" }
    if ($hostLiveNorm -notmatch "(?m)^GETMISS null$") { throw "host missing GETMISS null" }

    Inline-Guest "redis-live-prove.vire" "data/redis-live-prove.vire"
    $liveHexRel = "data/redis-live-prove.hex"
    if (Test-Path (Join-Path $Root $liveHexRel)) { Remove-Item -Force (Join-Path $Root $liveHexRel) }
    $compileLive = Invoke-Vire compile-native.vire "data/redis-live-prove.vire" $liveHexRel
    if ($compileLive -ne 0) { throw "compile-native redis-live exit $compileLive" }
    $liveExe = Join-Path $Data "redis-live-prove.exe"
    Convert-HexToExe (Join-Path $Root $liveHexRel) $liveExe
    try { Unblock-File -Path $liveExe } catch { }
    $ascii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($liveExe))
    if ($ascii -notmatch "ws2_32.dll") { throw "live PE missing ws2_32.dll" }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $peLive = & $liveExe $livePortText
    $peLiveCode = $LASTEXITCODE
    $sw.Stop()
    Write-Output $peLive
    Write-Output "redis_live_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
    Write-Output "redis_live_pe_exit $peLiveCode"
    if ($peLiveCode -ne 0) { throw "redis live PE exit $peLiveCode" }
    $peLiveNorm = (($peLive | Out-String) -replace '\r', '').Trim()
    if ($hostLiveNorm -ne $peLiveNorm) {
        Write-Output "HOST_PE_MISMATCH live"
        throw "host interpreter and gen1 PE live stdout differ"
    }
    Write-Output "PASS_AFTER at $AfterSha host and gen1 PE redis live stdout identical"
} finally {
    try { Stop-Process -Id $redis.Proc.Id -Force } catch { }
}

Write-Output "gen1_hello_and_gen2_sha covered by job native-selfhost-windows on this PR"
Write-Output "redis windows prove ok"
