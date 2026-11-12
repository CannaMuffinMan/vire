# Fail-before / pass-after: native guest outbound TCP on loopback.
# Echo fixture is pwsh/.NET only. Guest has no TLS. Caps unchanged.
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
$BaseSha = "d89edb29743c580613816d19cb1e7c749bce71e6"
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
if ($oldNative -match 'nm == "connect"') { throw "base compile-native already has connect" }
if ($oldNative -notmatch 'define main') { throw "fail-before snapshot missing define main" }
$oldSrc = Join-Path $Root "compile-native-fail-before.vire"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($oldSrc, $oldNative + "`n", $utf8)
Set-Content -Path (Join-Path $Data "tcp-fail-before.vire") -Value "define main`n  connect with `"127.0.0.1`", 9`nend`n"
$probeHex = Join-Path $Data "tcp-fail-before.hex"
if (Test-Path $probeHex) { Remove-Item -Force $probeHex }
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
try {
    $beforeOut = & dotnet exec $VireDll --compiler "compile-native-fail-before.vire" "data/tcp-fail-before.vire" "data/tcp-fail-before.hex" 2>&1 | Out-String
    $beforeCode = $LASTEXITCODE
} finally {
    if (Test-Path $oldSrc) { Remove-Item -Force $oldSrc }
}
$env:VIRE_BUDGET = "5000000"
Write-Output $beforeOut.TrimEnd()
Write-Output "fail_before_compile_exit $beforeCode"
if ($beforeCode -eq 0) { throw "fail-before compile unexpectedly succeeded" }
if ($beforeOut -notmatch "there is no definition named connect") {
    throw "fail-before missing unavailable connect"
}
Write-Output "FAIL_BEFORE at $BaseSha showing connect is unavailable"

Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading;
public class VireTcpEcho {
    public TcpListener Listener;
    Thread worker;
    volatile bool stop;
    public int Start() {
        Listener = new TcpListener(IPAddress.Parse("127.0.0.1"), 0);
        Listener.Start();
        worker = new Thread(Run);
        worker.IsBackground = true;
        worker.Start();
        return ((IPEndPoint)Listener.LocalEndpoint).Port;
    }
    void Run() {
        try {
            while (!stop) {
                TcpClient client = Listener.AcceptTcpClient();
                try {
                    NetworkStream stream = client.GetStream();
                    byte[] buf = new byte[4096];
                    int n = stream.Read(buf, 0, buf.Length);
                    if (n > 0) stream.Write(buf, 0, n);
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
$echoFix = New-Object VireTcpEcho
$port = $echoFix.Start()
Write-Output "echo_listen 127.0.0.1:$port"

Copy-Item (Join-Path $Root "tests/native/tcp-client.vire") (Join-Path $Data "tcp-client.vire") -Force
$portText = [string]$port

Write-Output "tcp_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostOut = & dotnet exec $VireDll "data/tcp-client.vire" $portText
$hostCode = $LASTEXITCODE
$sw.Stop()
Write-Output $hostOut
Write-Output "tcp_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "tcp_host_exit $hostCode"
if ($hostCode -ne 0) { throw "host tcp-client exit $hostCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
if ($hostNorm -notmatch "(?m)^ping$") { throw "host missing ping echo" }
if ($hostNorm -notmatch "refused-port") { throw "host missing refused-port" }
if ($hostNorm -notmatch "connect stays off this machine and private networks") {
    throw "host missing private-network sentence"
}
if ($hostNorm -notmatch "(?m)^2$") { throw "host missing bounded recv length 2" }

$hexRel = "data/tcp-client.hex"
$hexPath = Join-Path $Root $hexRel
if (Test-Path $hexPath) { Remove-Item -Force $hexPath }
$compileCode = Invoke-Vire compile-native.vire "data/tcp-client.vire" $hexRel
if ($compileCode -ne 0) { throw "compile-native tcp-client exit $compileCode" }
$exe = Join-Path $Data "tcp-client.exe"
Convert-HexToExe $hexPath $exe
$peBytes = [System.IO.File]::ReadAllBytes($exe)
$ascii = [System.Text.Encoding]::ASCII.GetString($peBytes)
if ($ascii -notmatch "connect") { throw "PE missing connect import name" }
if ($ascii -notmatch "ws2_32.dll") { throw "PE missing ws2_32.dll" }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peOut = & $exe $portText
$peCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peOut
Write-Output "tcp_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "tcp_pe_exit $peCode"
if ($peCode -ne 0) { throw "tcp PE exit $peCode" }
$peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH"
    Write-Output "HOST $hostNorm"
    Write-Output "PE $peNorm"
    throw "host interpreter and gen1 PE stdout differ"
}
Write-Output "PASS_AFTER at $AfterSha host and gen1 PE tcp stdout identical"
Write-Output "native tcp windows ok"

try { $echoFix.Halt() } catch { }
