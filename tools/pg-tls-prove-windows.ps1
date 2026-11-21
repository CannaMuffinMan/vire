# Host interpreter vs gen1 native PE: Postgres SSLRequest + Schannel + SCRAM on loopback.
# CouchStation: host stdout == PE stdout; PE must import secur32.dll; caps 32MB/100000/5M.
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
    $beforeOut = & dotnet exec $pinDll "data/pg-tls-fail-before.vire" 2>&1 | Out-String
    $beforeCode = $LASTEXITCODE
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

function Find-PgBin {
    $candidates = @()
    if ($env:PGBIN) { $candidates += $env:PGBIN }
    $candidates += @("C:\pgsql\bin", "C:\PostgreSQL\16\bin", "C:\Program Files\PostgreSQL\16\bin")
    Get-ChildItem "C:\Program Files\PostgreSQL" -ErrorAction SilentlyContinue | ForEach-Object {
        $candidates += (Join-Path $_.FullName "bin")
    }
    foreach ($dir in $candidates) {
        if (Test-Path (Join-Path $dir "initdb.exe")) { return $dir }
    }
    return $null
}

$PgBin = Find-PgBin
if (-not $PgBin) { throw "PostgreSQL binaries not found; install 16 for CouchStation TLS prove" }
$PgData = Join-Path $Data "pgtlsdata"
$PgLog = Join-Path $Data "pgtls.log"
$PgPort = 55433
if ($env:PGPORT) { $PgPort = [int]$env:PGPORT }
$PgUser = "vire"
$PgDb = "vire"
$pgctl = Join-Path $PgBin "pg_ctl.exe"
if (Test-Path $PgData) {
    & $pgctl -D $PgData -m fast -w stop 2>$null
    Remove-Item -Recurse -Force $PgData -ErrorAction SilentlyContinue
}
$alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$buf = New-Object byte[] 20
$rng.GetBytes($buf)
$chars = New-Object char[] 20
for ($i = 0; $i -lt 20; $i++) { $chars[$i] = $alphabet[$buf[$i] % $alphabet.Length] }
$PgSecret = -join $chars
Write-Output "pg_secret_len $($PgSecret.Length)"
$initdb = Join-Path $PgBin "initdb.exe"
$createdb = Join-Path $PgBin "createdb.exe"
$psql = Join-Path $PgBin "psql.exe"
& $initdb -D $PgData -U $PgUser --auth=trust --auth-local=trust --no-sync --locale=C --encoding=UTF8
if ($LASTEXITCODE -ne 0) { throw "initdb exit $LASTEXITCODE" }
$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) { throw "openssl required to mint throwaway test CA" }
& openssl req -x509 -newkey rsa:2048 -keyout (Join-Path $Data "pg-ca.key") -out (Join-Path $Data "pg-ca.pem") -days 1 -nodes -subj "/CN=vire-test-ca"
& openssl req -newkey rsa:2048 -keyout (Join-Path $PgData "server.key") -out (Join-Path $Data "pg-server.csr") -nodes -subj "/CN=localhost"
$ext = Join-Path $Data "pg-san.ext"
Set-Content -Path $ext -Value "subjectAltName=DNS:localhost,IP:127.0.0.1"
& openssl x509 -req -in (Join-Path $Data "pg-server.csr") -CA (Join-Path $Data "pg-ca.pem") -CAkey (Join-Path $Data "pg-ca.key") -CAcreateserial -out (Join-Path $PgData "server.crt") -days 1 -extfile $ext
Copy-Item (Join-Path $Data "pg-ca.pem") (Join-Path $PgData "root.crt")
& openssl req -x509 -newkey rsa:2048 -keyout (Join-Path $Data "pg-untrusted.key") -out (Join-Path $Data "pg-untrusted.pem") -days 1 -nodes -subj "/CN=untrusted-ca"
Add-Content -Path (Join-Path $PgData "postgresql.conf") -Value "`nlisten_addresses = '127.0.0.1'`nport = $PgPort`nunix_socket_directories = ''`npassword_encryption = scram-sha-256`nscram_iterations = 32`nssl = on`nssl_cert_file = 'server.crt'`nssl_key_file = 'server.key'`nssl_ca_file = 'root.crt'`n"
Set-Content -Path (Join-Path $PgData "pg_hba.conf") -Value @"
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 reject
host    all             all             0.0.0.0/0               reject
"@
& $pgctl -D $PgData -l $PgLog -o "-h 127.0.0.1 -p $PgPort" -w start
if ($LASTEXITCODE -ne 0) { throw "pg_ctl start exit $LASTEXITCODE" }
try {
    & $createdb -h 127.0.0.1 -p $PgPort -U $PgUser $PgDb
    & $psql -h 127.0.0.1 -p $PgPort -U $PgUser -d $PgDb -v ON_ERROR_STOP=1 -c "ALTER USER $PgUser PASSWORD '$PgSecret';"
    Set-Content -Path (Join-Path $PgData "pg_hba.conf") -Value @"
local   all             all                                     trust
hostssl all             all             127.0.0.1/32            scram-sha-256
hostnossl all           all             127.0.0.1/32            reject
host    all             all             ::1/128                 reject
host    all             all             0.0.0.0/0               reject
"@
    & $pgctl -D $PgData reload
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
    foreach ($n in @("non-loopback refused", "auth scram-sha-256", "select1 1", "paramless 42", "PG TLS PROVE pass")) {
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
    $compileCode = Invoke-Vire compile-native.vire "data/pg-tls-run.vire" "data/pg-tls-client.hex"
    if ($compileCode -ne 0) { throw "compile-native pg-tls exit $compileCode" }
    $exe = Join-Path $Data "pg-tls-client.exe"
    Convert-HexToExe (Join-Path $Root "data/pg-tls-client.hex") $exe
    $peBytes = [IO.File]::ReadAllBytes($exe)
    $ascii = [Text.Encoding]::ASCII.GetString($peBytes).ToLowerInvariant()
    if (-not $ascii.Contains("secur32.dll")) { throw "pg TLS PE missing secur32.dll" }
    if (-not $ascii.Contains("crypt32.dll")) { throw "pg TLS PE missing crypt32.dll" }
    $peOut = & $exe
    $peCode = $LASTEXITCODE
    Write-Output $peOut
    Write-Output "pg_tls_pe_exit $peCode"
    if ($peCode -ne 0) { throw "pg TLS PE exit $peCode" }
    $hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
    $peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
    if ($hostNorm -ne $peNorm) { throw "HOST_PE_MISMATCH" }
    Write-Output "pg tls host pe match"
    Write-Output "PASS_AFTER at $AfterSha host and gen1 PE pg-tls stdout identical"
    Write-Output "pg windows tls prove ok"
} finally {
    & $pgctl -D $PgData -m fast -w stop
}
