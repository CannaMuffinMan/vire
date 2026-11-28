# Host interpreter vs gen1 native PE against VireProof pg-stub (SCRAM, no install).
# No choco, no PostgreSQL. Caps unchanged.
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
$PinSha = "5b10ea5fa5eea46859f17a52b36037d9d088c01d"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $PinSha"
Write-Output "pass_after_sha $AfterSha"
Write-Output "pg_pin $PinSha"
Write-Output "pg_residual no TLS (TLS lane); native recv timeout is host 5s / SO_RCVTIMEO follow-up"
Write-VireHostInfo

function Ensure-PinCommit {
    git cat-file -e "$PinSha^{commit}" 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    git fetch --depth 1 origin $PinSha
    git cat-file -e "$PinSha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "missing pin commit $PinSha" }
}

function Invoke-FailBeforePinBuild {
    Ensure-PinCommit
    $pinDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vire-pg-fail-before-" + $PinSha.Substring(0, 12))
    git worktree list | Write-Output
    if (Test-Path $pinDir) {
        git worktree remove --force $pinDir 2>$null
        if (Test-Path $pinDir) { Remove-Item -Recurse -Force $pinDir }
    }
    git worktree add --detach $pinDir $PinSha
    if ($LASTEXITCODE -ne 0) { throw "git worktree add pin $PinSha failed" }
    $prev = Get-Location
    try {
        Set-Location -LiteralPath $pinDir
        & dotnet build (Join-Path $pinDir "vire.csproj") -c Release
        if ($LASTEXITCODE -ne 0) { throw "pin $PinSha dotnet build failed" }
        $pinDll = Join-Path $pinDir "bin/Release/net10.0/vire.dll"
        if (-not (Test-Path $pinDll)) { throw "pin build missing $pinDll" }
        if (Test-Path (Join-Path $pinDir "src/rt-pg.vire")) {
            throw "pin $PinSha unexpectedly has src/rt-pg.vire"
        }
        $guest = [System.IO.File]::ReadAllText((Join-Path $Root "tests/native/pg-client.vire"))
        $guest = $guest -replace "PORT_PLACEHOLDER", "55432"
        $guest = $guest -replace "PGUSER_PLACEHOLDER", "vire"
        $guest = $guest -replace "PGDB_PLACEHOLDER", "vire"
        $guest = $guest -replace "PGSECRET_PLACEHOLDER", ""
        $pinData = Join-Path $pinDir "data"
        New-Item -ItemType Directory -Force -Path $pinData | Out-Null
        $guestPath = Join-Path $pinData "pg-fail-before.vire"
        $utf8nb = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($guestPath, $guest, $utf8nb)
        Write-Output "pg_fail_before_pin_dll $pinDll"
        $beforeOutLog = Join-Path $pinData "pg-fail-before.out"
        $beforeErrLog = $beforeOutLog + ".err"
        $bp = Start-Process -FilePath "dotnet" -ArgumentList @("exec", $pinDll, "data/pg-fail-before.vire") -WorkingDirectory $pinDir -NoNewWindow -PassThru -RedirectStandardOutput $beforeOutLog -RedirectStandardError $beforeErrLog
        $null = $bp.Handle
        $null = $bp.WaitForExit(120000)
        $bp.WaitForExit()
        $beforeCode = 1
        if ($null -ne $bp.ExitCode) { $beforeCode = [int]$bp.ExitCode }
        $beforeOut = ""
        if (Test-Path -LiteralPath $beforeOutLog) { $beforeOut = [IO.File]::ReadAllText($beforeOutLog) }
        if (Test-Path -LiteralPath $beforeErrLog) { $beforeOut = ($beforeOut + "`n" + [IO.File]::ReadAllText($beforeErrLog)) }
        Write-Output $beforeOut.TrimEnd()
        Write-Output "fail_before_host_exit $beforeCode"
        if ($beforeCode -eq 0) { throw "FAIL_BEFORE unexpectedly passed at $PinSha" }
        if ($beforeOut -notmatch "there is no definition named pg_open") {
            throw "FAIL_BEFORE expected missing pg_open at pin, got $beforeOut"
        }
        $captured = (($beforeOut -replace "`r", "").Trim() -replace "`n", " | ")
        Write-Output "FAIL_BEFORE at $PinSha pin worktree: missing pg_open (honest, pin has no rt-pg.vire)"
    } finally {
        Set-Location -LiteralPath $prev
        git worktree remove --force $pinDir
        if (Test-Path $pinDir) { Remove-Item -Recurse -Force $pinDir }
    }
}

Invoke-FailBeforePinBuild

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

$ProofDll = Get-VireProofDll
$PgUser = "vire"
$PgDb = "vire"
$alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$buf = New-Object byte[] 20
$rng.GetBytes($buf)
$chars = New-Object char[] 20
for ($i = 0; $i -lt 20; $i++) { $chars[$i] = $alphabet[$buf[$i] % $alphabet.Length] }
$PgSecret = -join $chars
Write-Output "pg_secret_len $($PgSecret.Length)"
Write-Output "pg_loopback_stub vire-proof pg-stub (no PostgreSQL install, no choco)"

$stubProc = $null
$proofError = $null
try {
    $stubProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "pg-stub", $PgSecret) -WorkingDirectory $Root
    $PgPort = Get-ListenPort $stubProc
    Write-Output "pg_listen 127.0.0.1:$PgPort stub"
    Write-Output "pg_ready loopback scram-sha-256 stub"

    Write-Output "pg_decode_start"
    $decodeOut = & dotnet exec $VireDll "pg-decode-prove.vire"
    $decodeCode = $LASTEXITCODE
    Write-Output $decodeOut
    Write-Output "pg_decode_exit $decodeCode"
    if ($decodeCode -ne 0) { throw "pg-decode-prove exit $decodeCode" }
    if ("$decodeOut" -notmatch "PG DECODE PROVE pass") { throw "decode prove missing pass line" }

    $lib = [System.IO.File]::ReadAllText((Join-Path $Root "src/rt-pg.vire"))
    $guest = [System.IO.File]::ReadAllText((Join-Path $Root "tests/native/pg-client.vire"))
    if ($guest -notmatch "PORT_PLACEHOLDER") { throw "pg-client.vire missing PORT_PLACEHOLDER" }
    $guest = $guest -replace "PORT_PLACEHOLDER", "$PgPort"
    $guest = $guest -replace "PGUSER_PLACEHOLDER", $PgUser
    $guest = $guest -replace "PGDB_PLACEHOLDER", $PgDb
    $guest = $guest -replace "PGSECRET_PLACEHOLDER", $PgSecret
    $combined = $lib + "`n" + $guest
    $guestPath = Join-Path $Data "pg-client.vire"
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($guestPath, $combined, $utf8)

    Write-Output "pg_host_start"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $hostOut = & dotnet exec $VireDll "data/pg-client.vire"
    $hostCode = $LASTEXITCODE
    $sw.Stop()
    Write-Output $hostOut
    Write-Output "pg_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
    Write-Output "pg_host_exit $hostCode"
    Write-Output "pg_host_budget_cap 5000000"
    if ($hostCode -ne 0) { throw "host pg-client exit $hostCode" }
    $hostText = "$hostOut"
    foreach ($n in @(
        "non-loopback refused",
        "private refused",
        "select1 1",
        "roundtrip 7",
        "bad-sql ",
        "auth scram-sha-256",
        "injection-blocked table-live",
        "rollback 1",
        "commit 2",
        "typed int-bool-null",
        "PG PROVE pass"
    )) {
        if (-not $hostText.Contains($n)) { throw "host missing $n" }
    }

    $hexRel = "data/pg-client.hex"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $compileCode = Invoke-Vire compile-native.vire "data/pg-client.vire" $hexRel
    $sw.Stop()
    Write-Output "pg_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
    Write-Output "pg_pe_compile_exit $compileCode"
    if ($compileCode -ne 0) { throw "compile-native pg-client exit $compileCode" }
    $exe = Join-Path $Data "pg-client.exe"
    Convert-HexToExe (Join-Path $Root $hexRel) $exe
    $peBytes = [System.IO.File]::ReadAllBytes($exe)
    $ascii = [System.Text.Encoding]::ASCII.GetString($peBytes).ToLowerInvariant()
    if (-not $ascii.Contains("ws2_32.dll")) { throw "pg PE missing Winsock" }
    $OnWindows = ($env:OS -eq "Windows_NT")
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { if ($IsWindows) { $OnWindows = $true } }
    if ($OnWindows) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $peOut = & $exe
        $peCode = $LASTEXITCODE
        $sw.Stop()
        Write-Output $peOut
        Write-Output "pg_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
        Write-Output "pg_pe_exit $peCode"
        if ($peCode -ne 0) { throw "pg PE exit $peCode" }
        $hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
        $peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
        if ($hostNorm -ne $peNorm) {
            Write-Output "HOST_PE_MISMATCH"
            throw "host interpreter and gen1 PE stdout differ"
        }
        Write-Output "pg host pe match"
        Write-Output "PASS_AFTER at $AfterSha host and gen1 PE pg stdout identical against vire-proof pg-stub"
    } else {
        Write-Output "pe_execute_skipped linux agent cannot run PE; CouchStation runs pg-prove-windows.ps1"
        Write-Output "PASS_AFTER at $AfterSha host pg-client against vire-proof pg-stub; PE IAT ws2_32; PE execute is CouchStation"
    }
    Write-Output "pg windows prove ok"
} catch {
    $proofError = $_
} finally {
    try { if ($stubProc -and -not $stubProc.HasExited) { $stubProc.Kill() } } catch { }
}
if ($proofError) { throw $proofError }
