# Host interpreter vs gen1 native PE: Redis RESP2 over TLS (rediss:// verify-full).
# CouchStation: throwaway CA at test time; redis-server must support tls-port.
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
    $beforeOut = & dotnet exec $pinDll "data/redis-tls-fail-before.vire" 2>&1 | Out-String
    $beforeCode = $LASTEXITCODE
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

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) { throw "openssl required to mint throwaway test CA" }

$redis = Get-Command redis-server -ErrorAction SilentlyContinue
if (-not $redis) {
    $redis = Get-Command redis-server.exe -ErrorAction SilentlyContinue
}
if (-not $redis) {
    Write-Output "REDIS_TLS_SERVER_UNAVAILABLE no redis-server with tls-port on this Windows host"
    Write-Output "live rediss:// against a real Redis TLS binary was not executed"
    throw "redis tls windows prove cannot pass without redis-server tls-port (Redis 6+)"
}
$help = & $redis.Source --help 2>&1 | Out-String
if ($help -notmatch "tls-port") {
    Write-Output "REDIS_TLS_SERVER_UNAVAILABLE redis-server lacks tls-port"
    throw "redis tls windows prove cannot pass without redis-server tls-port (Redis 6+)"
}

$TlsPort = 16380
$PlainPort = 16379
$ExpPort = 16381
$alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$buf = New-Object byte[] 20
$rng.GetBytes($buf)
$chars = New-Object char[] 20
for ($i = 0; $i -lt 20; $i++) { $chars[$i] = $alphabet[$buf[$i] % $alphabet.Length] }
$Secret = -join $chars
Write-Output "redis_secret_len $($Secret.Length)"

& openssl req -x509 -newkey rsa:2048 -keyout (Join-Path $Data "redis-ca.key") -out (Join-Path $Data "redis-ca.pem") -days 1 -nodes -subj "/CN=vire-redis-test-ca"
& openssl req -newkey rsa:2048 -keyout (Join-Path $Data "redis-server.key") -out (Join-Path $Data "redis-server.csr") -nodes -subj "/CN=localhost"
$ext = Join-Path $Data "redis-san.ext"
Set-Content -Path $ext -Value "subjectAltName=DNS:localhost,IP:127.0.0.1"
& openssl x509 -req -in (Join-Path $Data "redis-server.csr") -CA (Join-Path $Data "redis-ca.pem") -CAkey (Join-Path $Data "redis-ca.key") -CAcreateserial -out (Join-Path $Data "redis-server.crt") -days 1 -extfile $ext
& openssl req -x509 -newkey rsa:2048 -keyout (Join-Path $Data "redis-untrusted.key") -out (Join-Path $Data "redis-untrusted.pem") -days 1 -nodes -subj "/CN=untrusted-ca"
& openssl req -newkey rsa:2048 -keyout (Join-Path $Data "redis-expired.key") -out (Join-Path $Data "redis-expired.csr") -nodes -subj "/CN=localhost"
$caDb = Join-Path $Data "redis-ca-db"
New-Item -ItemType Directory -Force -Path $caDb | Out-Null
Set-Content -Path (Join-Path $caDb "serial") -Value "1000"
Set-Content -Path (Join-Path $caDb "index.txt") -Value ""
$cnf = Join-Path $Data "redis-ca.cnf"
$caPemUnix = ((Join-Path $Data "redis-ca.pem") -replace '\\','/')
$caKeyUnix = ((Join-Path $Data "redis-ca.key") -replace '\\','/')
$caDbUnix = ($caDb -replace '\\','/')
@"
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = $caDbUnix
database = $caDbUnix/index.txt
serial = $caDbUnix/serial
new_certs_dir = $caDbUnix
certificate = $caPemUnix
private_key = $caKeyUnix
default_md = sha256
policy = policy_any
x509_extensions = usr_cert
default_startdate = 200101010000Z
default_enddate = 200101020000Z
[ policy_any ]
commonName = supplied
[ usr_cert ]
subjectAltName=DNS:localhost,IP:127.0.0.1
basicConstraints=CA:FALSE
"@ | Set-Content -Path $cnf
& openssl ca -config $cnf -in (Join-Path $Data "redis-expired.csr") -out (Join-Path $Data "redis-expired.crt") -batch -notext

function Write-RedisTlsConf([string]$Path, [int]$Port, [int]$TlsPortNum, [string]$Cert, [string]$Key, [string]$Require) {
    @"
bind 127.0.0.1
protected-mode yes
port $Port
tls-port $TlsPortNum
tls-cert-file $($Cert -replace '\\','/')
tls-key-file $($Key -replace '\\','/')
tls-ca-cert-file $((Join-Path $Data 'redis-ca.pem') -replace '\\','/')
tls-auth-clients no
tls-protocols "TLSv1.2 TLSv1.3"
requirepass $Require
daemonize no
dir $($Data -replace '\\','/')
dbfilename redis-tls-$TlsPortNum.rdb
logfile $((Join-Path $Data "redis-tls-$TlsPortNum.log") -replace '\\','/')
save ""
"@ | Set-Content -Path $Path
}

$conf = Join-Path $Data "redis-tls.conf"
$expConf = Join-Path $Data "redis-tls-expired.conf"
Write-RedisTlsConf $conf $PlainPort $TlsPort (Join-Path $Data "redis-server.crt") (Join-Path $Data "redis-server.key") $Secret
Write-RedisTlsConf $expConf 0 $ExpPort (Join-Path $Data "redis-expired.crt") (Join-Path $Data "redis-expired.key") $Secret

$proc = Start-Process -FilePath $redis.Source -ArgumentList @($conf) -WorkingDirectory $Data -PassThru -WindowStyle Hidden
$expProc = Start-Process -FilePath $redis.Source -ArgumentList @($expConf) -WorkingDirectory $Data -PassThru -WindowStyle Hidden

function Wait-Port([int]$Port) {
    $ok = $false
    for ($i = 0; $i -lt 80; $i++) {
        Start-Sleep -Milliseconds 50
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $c.Connect("127.0.0.1", $Port)
            $c.Close()
            $ok = $true
            break
        } catch { }
    }
    if (-not $ok) { throw "redis never listened on 127.0.0.1:$Port" }
}

try {
    Wait-Port $TlsPort
    Wait-Port $PlainPort
    Wait-Port $ExpPort
    Write-Output "redis_listen 127.0.0.1:${TlsPort} tls"
    Write-Output "redis_listen 127.0.0.1:${PlainPort} plaintext"
    Write-Output "redis_listen 127.0.0.1:${ExpPort} expired-tls"

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

    $compileCode = Invoke-Vire compile-native.vire "data/redis-tls-run.vire" "data/redis-tls-client.hex"
    if ($compileCode -ne 0) { throw "compile-native redis-tls exit $compileCode" }
    $exe = Join-Path $Data "redis-tls-client.exe"
    Convert-HexToExe (Join-Path $Root "data/redis-tls-client.hex") $exe
    try { Unblock-File -Path $exe } catch { }
    $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($exe)).ToLowerInvariant()
    if (-not $ascii.Contains("secur32.dll")) { throw "redis TLS PE missing secur32.dll" }
    $peOut = & $exe
    $peCode = $LASTEXITCODE
    Write-Output $peOut
    Write-Output "redis_tls_pe_exit $peCode"
    if ($peCode -ne 0) { throw "redis TLS PE exit $peCode" }
    $hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
    $peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
    if ($hostNorm -ne $peNorm) { throw "HOST_PE_MISMATCH" }
    Write-Output "redis tls host pe match"
    Write-Output "PASS_AFTER at $AfterSha host and gen1 PE redis-tls stdout identical"
    Write-Output "redis windows tls prove ok"
} finally {
    try { Stop-Process -Id $proc.Id -Force } catch { }
    try { Stop-Process -Id $expProc.Id -Force } catch { }
}
