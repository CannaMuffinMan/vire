# Host interpreter vs gen1 native PE: Redis RESP2 over TLS (rediss:// verify-full).
# CouchStation has no redis-server tls-port. VireProof redis-tls-stub is the loopback server.
# Caps 32MB/100000/5M. Loopback 127.0.0.1 only. Windows Defender untouched.
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
$PinSha = "f085dff6770513cfc9660f1a712967e177cf5b50"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $PinSha"
Write-Output "pass_after_sha $AfterSha"
Write-Output "redis_tls_residual no RESP3 no ACL username"
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

git cat-file -e "$PinSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { git fetch --depth 1 origin $PinSha }
$pinDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vire-redis-tls-fail-before-" + $PinSha.Substring(0, 12))
if (Test-Path $pinDir) { git worktree remove --force $pinDir 2>$null; if (Test-Path $pinDir) { Remove-Item -Recurse -Force $pinDir } }
git worktree add --detach $pinDir $PinSha
$prev = Get-Location
try {
    Set-Location -LiteralPath $pinDir
    & dotnet build (Join-Path $pinDir "vire.csproj") -c Release
    if ($LASTEXITCODE -ne 0) { throw "pin build failed" }
    $pinDll = Join-Path $pinDir "bin/Release/net10.0/vire.dll"
    New-Item -ItemType Directory -Force -Path (Join-Path $pinDir "data") | Out-Null
    $utf8nb = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText((Join-Path $pinDir "data/redis-tls-fail-before.vire"), "define main`n  redis_open_tls with 16380, `"localhost`", `"data/redis-ca.pem`"`nend`n", $utf8nb)
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $beforeOut = & dotnet exec $pinDll "data/redis-tls-fail-before.vire" 2>&1 | Out-String
        $beforeCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedEap
    }
    Write-Output $beforeOut.TrimEnd()
    Write-Output "fail_before_host_exit $beforeCode"
    if ($beforeCode -eq 0) { throw "FAIL_BEFORE unexpectedly passed at $PinSha" }
    if ($beforeOut -notmatch "there is no definition named redis_open_tls") {
        throw "FAIL_BEFORE expected missing redis_open_tls"
    }
    Write-Output "FAIL_BEFORE at $PinSha pin worktree: missing redis_open_tls"
} finally {
    Set-Location -LiteralPath $prev
    git worktree remove --force $pinDir
    if (Test-Path $pinDir) { Remove-Item -Recurse -Force $pinDir }
}

# CouchStation has no Redis. This script starts a loopback rediss stub via VireProof.
$ProofDll = Get-VireProofDll
$pfx = Join-Path $Data "redis-tls.pfx"
$ca = Join-Path $Data "redis-ca.pem"
$untrustedPfx = Join-Path $Data "redis-untrusted.pfx"
$untrusted = Join-Path $Data "redis-untrusted.pem"
$expPfx = Join-Path $Data "redis-expired.pfx"
$expCer = Join-Path $Data "redis-expired.pem"
& dotnet exec $ProofDll write-pfx $pfx $ca "x"
if ($LASTEXITCODE -ne 0) { throw "write-pfx redis ca failed" }
& dotnet exec $ProofDll write-pfx $untrustedPfx $untrusted "x"
if ($LASTEXITCODE -ne 0) { throw "write-pfx redis untrusted failed" }
& dotnet exec $ProofDll write-pfx-expired $expPfx $expCer "x"
if ($LASTEXITCODE -ne 0) { throw "write-pfx-expired failed" }
$Secret = "x"
Write-Output "redis_secret_len $($Secret.Length)"
Write-Output "redis_loopback_stub vire-proof redis-tls-stub (no redis-server on CouchStation)"

$proc = $null
try {
    $proc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "redis-tls-stub", $pfx, "x", $expPfx, "x") -WorkingDirectory $Root
    $TlsPort = Get-ListenPort $proc
    $plainLine = $proc.StandardOutput.ReadLine()
    $expLine = $proc.StandardOutput.ReadLine()
    if ($plainLine -notmatch "listening-plain on 127.0.0.1:(\d+)") { throw "missing listening-plain: $plainLine" }
    $PlainPort = [int]$Matches[1]
    if ($expLine -notmatch "listening-expired on 127.0.0.1:(\d+)") { throw "missing listening-expired: $expLine" }
    $ExpPort = [int]$Matches[1]
    Write-Output "redis_listen 127.0.0.1:${TlsPort} tls-stub"
    Write-Output "redis_listen 127.0.0.1:${PlainPort} plaintext-stub"
    Write-Output "redis_listen 127.0.0.1:${ExpPort} expired-tls-stub"

    function Fill-Guest([string]$SrcRel, [string]$DestRel) {
        $lib = [IO.File]::ReadAllText((Join-Path $Root "src/rt-redis.vire"))
        $guest = [IO.File]::ReadAllText((Join-Path $Root $SrcRel))
        $guest = $guest.Replace("TLS_PORT_PLACEHOLDER", "$TlsPort")
        $guest = $guest.Replace("PLAIN_PORT_PLACEHOLDER", "$PlainPort")
        $guest = $guest.Replace("EXP_PORT_PLACEHOLDER", "$ExpPort")
        $guest = $guest.Replace("SECRET_PLACEHOLDER", $Secret)
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText((Join-Path $Root $DestRel), ($lib + "`n" + $guest), $utf8)
    }

    Fill-Guest "tests/native/redis-tls.vire" "redis-tls-run.vire"
    Fill-Guest "tests/native/redis-tls.vire" "data/redis-tls-run.vire"
    Write-Output "redis_tls_host_start"
    $hostOut = & dotnet exec $VireDll "redis-tls-run.vire"
    $hostCode = $LASTEXITCODE
    Write-Output $hostOut
    Write-Output "redis_tls_host_exit $hostCode"
    Write-Output "redis_host_budget_cap 5000000"
    if ($hostCode -ne 0) { throw "host redis-tls exit $hostCode" }
    foreach ($n in @("non-loopback refused", "plaintext-url ", "auth OK", "PING PONG", "SET OK", "GET hello", "REDIS TLS PROVE pass")) {
        if (-not "$hostOut".Contains($n)) { throw "host missing $n" }
    }

    Fill-Guest "tests/native/redis-tls-verify.vire" "redis-tls-verify-run.vire"
    $verifyOut = & dotnet exec $VireDll "redis-tls-verify-run.vire"
    if ($LASTEXITCODE -ne 0) { throw "host verify negatives exit $LASTEXITCODE" }
    Write-Output $verifyOut
    foreach ($n in @("wrong-host ", "untrusted-ca ", "expired-cert ", "REDIS TLS VERIFY pass")) {
        if (-not "$verifyOut".Contains($n)) { throw "host missing $n" }
    }

    Fill-Guest "tests/native/redis-tls-neg.vire" "redis-tls-neg-run.vire"
    $negOut = & dotnet exec $VireDll "redis-tls-neg-run.vire"
    if ($LASTEXITCODE -ne 0) { throw "host neg exit $LASTEXITCODE" }
    Write-Output $negOut
    foreach ($n in @("downgrade ", "REDIS TLS NEG pass")) {
        if (-not "$negOut".Contains($n)) { throw "host missing $n" }
    }

    $compileCode = Invoke-Vire compile-native.vire "data/redis-tls-run.vire" "data/redis-tls-client.hex" "pe"
    if ($compileCode -ne 0) { throw "compile-native redis-tls pe exit $compileCode" }
    $exe = Join-Path $Data "redis-tls-client.exe"
    Convert-HexToExe (Join-Path $Root "data/redis-tls-client.hex") $exe
    try { Unblock-File -Path $exe } catch { }
    $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($exe)).ToLowerInvariant()
    if (-not $ascii.Contains("secur32.dll")) { throw "redis TLS PE missing secur32.dll" }
    if ($ascii.Contains("loadlibrarya")) { throw "redis TLS PE LoadLibraryA forbidden" }
    Write-Output "redis_tls_pe_schannel_iat_ok"

    $OnWindows = ($env:OS -eq "Windows_NT")
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { if ($IsWindows) { $OnWindows = $true } }
    if ($OnWindows) {
        $peOut = & $exe
        $peCode = $LASTEXITCODE
        Write-Output $peOut
        Write-Output "redis_tls_pe_exit $peCode"
        if ($peCode -ne 0) { throw "redis TLS PE exit $peCode" }
        $hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
        $peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
        if ($hostNorm -ne $peNorm) { throw "HOST_PE_MISMATCH" }
        Write-Output "redis tls host pe match"
        Write-Output "PASS_AFTER at $AfterSha host and gen1 PE redis-tls stdout identical against loopback rediss stub"
    } else {
        Write-Output "pe_execute_skipped linux agent cannot run PE; CouchStation runs redis-tls-prove-windows.ps1"
        Write-Output "PASS_AFTER at $AfterSha host redis-tls against loopback rediss stub; PE IAT SChannel; PE execute is CouchStation"
    }
    Write-Output "redis windows tls prove ok"
} finally {
    try { if ($proc -and -not $proc.HasExited) { $proc.Kill() } } catch { }
}
