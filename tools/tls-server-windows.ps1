# Host SslStream TLS listener proof for CouchStation.
# Self-signed certs generated at run time. Loopback 127.0.0.1 only.
# Caps unchanged. Native PE tls_listen stays fail-closed until SChannel.
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
$BaseSha = "5c1f89adb5952f6c72037edbc8a856c3fd03bfdf"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --depth 1 origin $BaseSha
}
$oldTls = (& git -C $Root show "${BaseSha}:src/rt-tls.vire") -join "`n"
if ($oldTls -notmatch "native tls_listen is fail-closed") {
    throw "FAIL_BEFORE expected fail-closed tls_listen at $BaseSha"
}
Write-Output "FAIL_BEFORE at $BaseSha native tls_listen fail-closed"

$ProofDll = Get-VireProofDll
$certPath = Join-Path $Data "tls-health-cert.pem"
$keyPath = Join-Path $Data "tls-health-key.pem"
& dotnet exec $ProofDll write-pem $certPath $keyPath
if ($LASTEXITCODE -ne 0) { throw "write-pem failed" }

$src = Join-Path $Data "guest-health-tls.vire"
Copy-Item -Force (Join-Path $Root "guest-health-tls.vire") $src
$contract = Get-Content -Raw (Join-Path $Root "tests/rebuild/contracts/health.json")
if ($contract -notmatch '"service":\s*"fcgcpa"') { throw "health contract missing fcgcpa" }

$proc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/guest-health-tls.vire") -WorkingDirectory $Root
$port = Get-ListenPort -Proc $proc -Seconds 15
Write-Output "tls_host_listen 127.0.0.1:$port"

$body = & dotnet exec $ProofDll https-health $port $certPath
if ($LASTEXITCODE -ne 0) { throw "https-health failed" }
Write-Output $body
if ($body -notmatch '"ok":true') { throw "health missing ok" }
if ($body -notmatch 'fcgcpa') { throw "health missing service" }
if ($body -notmatch '"payments":false') { throw "health payments must stay false" }
Write-Output "PASS_AFTER at $AfterSha host SslStream GET /health matches contract"
Write-Output "tls_server_windows ok"
try { $proc.Kill() } catch { }
