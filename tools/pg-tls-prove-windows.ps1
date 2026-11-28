# Host interpreter vs gen1 native PE: Postgres SSLRequest + Schannel on loopback.
# CouchStation has no PostgreSQL 16. VireProof pg-tls-stub speaks SSLRequest + TLS + trust.
# Host stdout == PE stdout; PE must import secur32.dll; caps 32MB/100000/5M.
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
$PinSha = "cd0bd38584e4d3faad0f46b4eefe98515b2dbf26"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $PinSha"
Write-Output "pass_after_sha $AfterSha"
Write-Output "pg_tls_residual no SCRAM-SHA-256-PLUS channel binding"
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
$pinDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vire-pg-tls-fail-before-" + $PinSha.Substring(0, 12))
if (Test-Path $pinDir) { git worktree remove --force $pinDir 2>$null; if (Test-Path $pinDir) { Remove-Item -Recurse -Force $pinDir } }
git worktree add --detach $pinDir $PinSha
$prev = Get-Location
try {
    Set-Location -LiteralPath $pinDir
    & dotnet build (Join-Path $pinDir "vire.csproj") -c Release
    if ($LASTEXITCODE -ne 0) { throw "pin build failed" }
    $pinDll = Join-Path $pinDir "bin/Release/net10.0/vire.dll"
    $guest = [IO.File]::ReadAllText((Join-Path $Root "tests/native/pg-tls.vire"))
    $guest = $guest -replace "PORT_PLACEHOLDER", "55433"
    $guest = $guest -replace "PGUSER_PLACEHOLDER", "vire"
    $guest = $guest -replace "PGDB_PLACEHOLDER", "vire"
    $guest = $guest -replace "PGSECRET_PLACEHOLDER", "x"
    New-Item -ItemType Directory -Force -Path (Join-Path $pinDir "data") | Out-Null
    $utf8nb = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText((Join-Path $pinDir "data/pg-tls-fail-before.vire"), $guest, $utf8nb)
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $beforeOut = & dotnet exec $pinDll "data/pg-tls-fail-before.vire" 2>&1 | Out-String
        $beforeCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedEap
    }
    Write-Output $beforeOut.TrimEnd()
    Write-Output "fail_before_host_exit $beforeCode"
    if ($beforeCode -eq 0) { throw "FAIL_BEFORE unexpectedly passed at $PinSha" }
    if ($beforeOut -notmatch "there is no definition named (pg_open_ssl|tls_wrap)") {
        throw "FAIL_BEFORE expected missing tls_wrap/pg_open_ssl"
    }
    Write-Output "FAIL_BEFORE at $PinSha pin worktree: missing TLS wrap"
} finally {
    Set-Location -LiteralPath $prev
    git worktree remove --force $pinDir
    if (Test-Path $pinDir) { Remove-Item -Recurse -Force $pinDir }
}

# CouchStation has no PostgreSQL 16. This script starts a loopback SSLRequest TLS stub
# via tools/VireProof (pg-tls-stub). Named skip only if vire-proof cannot start.
$ProofDll = Get-VireProofDll
$pfx = Join-Path $Data "pg-tls.pfx"
$ca = Join-Path $Data "pg-ca.pem"
$untrusted = Join-Path $Data "pg-untrusted.pem"
$untrustedPfx = Join-Path $Data "pg-untrusted.pfx"
& dotnet exec $ProofDll write-pfx $pfx $ca "x"
if ($LASTEXITCODE -ne 0) { throw "write-pfx pg ca failed" }
& dotnet exec $ProofDll write-pfx $untrustedPfx $untrusted "x"
if ($LASTEXITCODE -ne 0) { throw "write-pfx untrusted failed" }
$PgUser = "vire"
$PgDb = "vire"
$PgSecret = "x"
Write-Output "pg_secret_len $($PgSecret.Length)"
Write-Output "pg_loopback_stub vire-proof pg-tls-stub (no PostgreSQL 16 on CouchStation)"

$echoProc = $null
$nProc = $null
try {
    $echoProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "pg-tls-stub", $pfx, "x") -WorkingDirectory $Root
    $PgPort = Get-ListenPort $echoProc
    Write-Output "pg_listen 127.0.0.1:$PgPort tls-stub"
    $nProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "pg-tls-n") -WorkingDirectory $Root
    $NPort = Get-ListenPort $nProc
    Write-Output "pg_listen 127.0.0.1:$NPort sslrequest-N"

    $lib = [IO.File]::ReadAllText((Join-Path $Root "src/rt-pg.vire"))
    $guest = [IO.File]::ReadAllText((Join-Path $Root "tests/native/pg-tls.vire"))
    $guest = $guest -replace "PORT_PLACEHOLDER", "$PgPort"
    $guest = $guest -replace "PGUSER_PLACEHOLDER", $PgUser
    $guest = $guest -replace "PGDB_PLACEHOLDER", $PgDb
    $guest = $guest -replace "PGSECRET_PLACEHOLDER", $PgSecret
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText((Join-Path $Root "pg-tls-run.vire"), ($lib + "`n" + $guest), $utf8)
    [IO.File]::WriteAllText((Join-Path $Data "pg-tls-run.vire"), ($lib + "`n" + $guest), $utf8)
    Write-Output "pg_tls_host_start"
    $hostOut = & dotnet exec $VireDll "pg-tls-run.vire"
    $hostCode = $LASTEXITCODE
    Write-Output $hostOut
    Write-Output "pg_tls_host_exit $hostCode"
    Write-Output "pg_host_budget_cap 5000000"
    if ($hostCode -ne 0) { throw "host pg-tls exit $hostCode" }
    $hostText = "$hostOut"
    foreach ($n in @("non-loopback refused", "auth scram-sha-256-plus", "select1 1", "paramless 42", "PG TLS PROVE pass")) {
        if (-not $hostText.Contains($n)) { throw "host missing $n" }
    }
    $vguest = [IO.File]::ReadAllText((Join-Path $Root "tests/native/pg-tls-verify.vire"))
    $vguest = $vguest -replace "PORT_PLACEHOLDER", "$PgPort"
    $vguest = $vguest -replace "PGUSER_PLACEHOLDER", $PgUser
    $vguest = $vguest -replace "PGDB_PLACEHOLDER", $PgDb
    $vguest = $vguest -replace "PGSECRET_PLACEHOLDER", $PgSecret
    [IO.File]::WriteAllText((Join-Path $Root "pg-tls-verify-run.vire"), ($lib + "`n" + $vguest), $utf8)
    $verifyOut = & dotnet exec $VireDll "pg-tls-verify-run.vire"
    if ($LASTEXITCODE -ne 0) { throw "host verify negatives exit $LASTEXITCODE" }
    Write-Output $verifyOut
    foreach ($n in @("wrong-host ", "untrusted-ca ", "PG TLS VERIFY pass")) {
        if (-not "$verifyOut".Contains($n)) { throw "host missing $n" }
    }
    $nguest = [IO.File]::ReadAllText((Join-Path $Root "tests/native/pg-tls-neg.vire"))
    $nguest = $nguest -replace "NPORT_PLACEHOLDER", "$NPort"
    $nguest = $nguest -replace "SPORT_PLACEHOLDER", "$NPort"
    [IO.File]::WriteAllText((Join-Path $Root "pg-tls-neg-run.vire"), ($lib + "`n" + $nguest), $utf8)
    $negOut = & dotnet exec $VireDll "pg-tls-neg-run.vire"
    if ($LASTEXITCODE -ne 0) { throw "host neg exit $LASTEXITCODE" }
    Write-Output $negOut
    if (-not "$negOut".Contains("ssl-refused ")) { throw "host missing ssl-refused" }

    $compileCode = Invoke-Vire compile-native.vire "data/pg-tls-run.vire" "data/pg-tls-client.hex" "pe"
    if ($compileCode -ne 0) { throw "compile-native pg-tls pe exit $compileCode" }
    $exe = Join-Path $Data "pg-tls-client.exe"
    Convert-HexToExe (Join-Path $Root "data/pg-tls-client.hex") $exe
    $peBytes = [IO.File]::ReadAllBytes($exe)
    $ascii = [Text.Encoding]::ASCII.GetString($peBytes).ToLowerInvariant()
    if (-not $ascii.Contains("secur32.dll")) { throw "pg TLS PE missing secur32.dll" }
    if (-not $ascii.Contains("crypt32.dll")) { throw "pg TLS PE missing crypt32.dll" }
    if ($ascii.Contains("loadlibrarya")) { throw "pg TLS PE LoadLibraryA forbidden" }
    Write-Output "pg_tls_pe_schannel_iat_ok"

    $OnWindows = ($env:OS -eq "Windows_NT")
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { if ($IsWindows) { $OnWindows = $true } }
    if ($OnWindows) {
        $peOut = & $exe
        $peCode = $LASTEXITCODE
        Write-Output $peOut
        Write-Output "pg_tls_pe_exit $peCode"
        if ($peCode -ne 0) { throw "pg TLS PE exit $peCode" }
        $hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
        $peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
        if ($hostNorm -ne $peNorm) { throw "HOST_PE_MISMATCH" }
        Write-Output "pg tls host pe match"
        Write-Output "PASS_AFTER at $AfterSha host and gen1 PE pg-tls stdout identical against loopback SSLRequest stub"
    } else {
        Write-Output "pe_execute_skipped linux agent cannot run PE; CouchStation runs pg-tls-prove-windows.ps1"
        Write-Output "PASS_AFTER at $AfterSha host pg-tls against loopback SSLRequest stub; PE IAT SChannel; PE execute is CouchStation"
    }
    Write-Output "pg windows tls prove ok"
} finally {
    try { if ($echoProc -and -not $echoProc.HasExited) { $echoProc.Kill() } } catch { }
    try { if ($nProc -and -not $nProc.HasExited) { $nProc.Kill() } } catch { }
}
