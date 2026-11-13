# Host interpreter vs gen1 native PE against loopback PostgreSQL 16.
# Trust auth. No TLS. Caps unchanged. Throwaway CI password is for init only.
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
Write-Output "pg_residual no TLS; SCRAM-SHA-256 not used (5M cap); auth trust"
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
        $beforeOut = & dotnet exec $pinDll "data/pg-fail-before.vire" 2>&1 | Out-String
        $beforeCode = $LASTEXITCODE
        Write-Output $beforeOut.TrimEnd()
        Write-Output "fail_before_host_exit $beforeCode"
        if ($beforeCode -eq 0) { throw "FAIL_BEFORE unexpectedly passed at $PinSha" }
        if ($beforeOut -notmatch "there is no definition named pg_open") {
            throw "FAIL_BEFORE expected missing pg_open at pin, got $beforeOut"
        }
        $captured = (($beforeOut -replace "`r", "").Trim() -replace "`n", " | ")
        Write-Output "FAIL_BEFORE at $PinSha pin worktree build+run of tests/native/pg-client.vire: $captured"
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

function Find-PgBin {
    $candidates = @()
    if ($env:PGBIN) { $candidates += $env:PGBIN }
    $candidates += @(
        "C:\pgsql\bin",
        "C:\PostgreSQL\16\bin",
        "C:\Program Files\PostgreSQL\16\bin",
        "C:\Program Files\PostgreSQL\17\bin"
    )
    Get-ChildItem "C:\Program Files\PostgreSQL" -ErrorAction SilentlyContinue | ForEach-Object {
        $candidates += (Join-Path $_.FullName "bin")
    }
    foreach ($dir in $candidates) {
        if (Test-Path (Join-Path $dir "initdb.exe")) { return $dir }
    }
    return $null
}

function Install-Pg16 {
    Write-Output "pg_install chocolatey postgresql16"
    & choco install postgresql16 --yes --no-progress --params "/Password:ThrowawayVireCi1 /Port:55432"
    $bin = Find-PgBin
    if ($bin) { return $bin }
    throw "PostgreSQL 16 binaries not found after chocolatey install"
}

$PgBin = Find-PgBin
if (-not $PgBin) {
    try {
        $PgBin = Install-Pg16
    } catch {
        Write-Output "WINDOWS_PG_INSTALL_FAILED $($_.Exception.Message)"
        throw "Windows CI could not host PostgreSQL; PE-vs-Postgres not proven. $($_.Exception.Message)"
    }
}
Write-Output "pg_bin $PgBin"

$PgData = Join-Path $Data "pgdata"
$PgLog = Join-Path $Data "pg.log"
$PgPort = 55432
if ($env:PGPORT) { $PgPort = [int]$env:PGPORT }
$PgUser = "vire"
$PgDb = "vire"
if (Test-Path $PgData) { Remove-Item -Recurse -Force $PgData }
$initdb = Join-Path $PgBin "initdb.exe"
$pgctl = Join-Path $PgBin "pg_ctl.exe"
$createdb = Join-Path $PgBin "createdb.exe"
$env:PGPASSWORD = "ThrowawayVireCi1"
& $initdb -D $PgData -U $PgUser --auth=trust --auth-local=trust --no-sync --locale=C --encoding=UTF8
if ($LASTEXITCODE -ne 0) { throw "initdb exit $LASTEXITCODE" }
$conf = Join-Path $PgData "postgresql.conf"
Add-Content -Path $conf -Value "`nlisten_addresses = '127.0.0.1'`nport = $PgPort`nunix_socket_directories = ''`npassword_encryption = scram-sha-256`n"
$hba = Join-Path $PgData "pg_hba.conf"
Set-Content -Path $hba -Value @"
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 reject
host    all             all             0.0.0.0/0               reject
"@
Write-Output "pg_listen 127.0.0.1:$PgPort"
& $pgctl -D $PgData -l $PgLog -o "-h 127.0.0.1 -p $PgPort" -w start
if ($LASTEXITCODE -ne 0) {
    if (Test-Path $PgLog) { Get-Content $PgLog | Write-Output }
    throw "pg_ctl start exit $LASTEXITCODE"
}
$started = $true
try {
    & $createdb -h 127.0.0.1 -p $PgPort -U $PgUser $PgDb
    if ($LASTEXITCODE -ne 0) { throw "createdb exit $LASTEXITCODE" }
    Write-Output "pg_ready 16 loopback trust"

    $lib = [System.IO.File]::ReadAllText((Join-Path $Root "src/rt-pg.vire"))
    $guest = [System.IO.File]::ReadAllText((Join-Path $Root "tests/native/pg-client.vire"))
    if ($guest -notmatch "PORT_PLACEHOLDER") { throw "pg-client.vire missing PORT_PLACEHOLDER" }
    $guest = $guest -replace "PORT_PLACEHOLDER", "$PgPort"
    $guest = $guest -replace "PGUSER_PLACEHOLDER", $PgUser
    $guest = $guest -replace "PGDB_PLACEHOLDER", $PgDb
    $guest = $guest -replace "PGSECRET_PLACEHOLDER", ""
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
        "injection-blocked table-live",
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
    Write-Output "PASS_AFTER at $AfterSha host and gen1 PE pg stdout identical"
    Write-Output "pg windows prove ok"
} finally {
    if ($started) {
        try { & $pgctl -D $PgData -m fast -w stop | Out-Null } catch { }
    }
}
