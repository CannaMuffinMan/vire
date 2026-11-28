# CouchStation PE: RFC 6455 upgrade through reverse-proxy vs loopback ws-upstream.
# Linux ELF: tools/rebuild-proxy-ws-diff.sh. Do not claim PE proof from Linux.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "cec3896320411cccdc016f59fedd1114ffb823e3"
$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000"
Write-Host "FAIL_BEFORE at $FailBefore hop-by-hop Upgrade strip"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
$ProofDll = Get-VireProofDll
$stage = Join-Path $Root "data/native-proxy-ws-pe"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $stage "http-client.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/proxy-http.vire") (Join-Path $stage "proxy-http.vire") -Force
$hex = Join-Path $stage "proxy-http.hex"
$exe = Join-Path $stage "proxy-http.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
& dotnet exec $VireDll --compiler compile-native.vire data/native-proxy-ws-pe/proxy-http.vire data/native-proxy-ws-pe/proxy-http.hex pe
if ($LASTEXITCODE -ne 0) { throw "compile exit $LASTEXITCODE" }
$hexText = (Get-Content -Raw $hex).Trim()
$pe = New-Object byte[] ($hexText.Length / 2)
for ($i = 0; $i -lt $pe.Length; $i++) { $pe[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16) }
[IO.File]::WriteAllBytes($exe, $pe)

$up = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "ws-upstream") -WorkingDirectory $Root
$upPort = Get-ListenPort $up
Write-Host "upstream 127.0.0.1:$upPort"

function Run-Mode([string]$Mode, [string]$Want) {
    $hostOut = & dotnet exec $VireDll data/native-proxy-ws-pe/proxy-http.vire "$upPort" $Mode | Out-String
    $peOut = & $exe "$upPort" $Mode | Out-String
    Write-Host "--- mode $Mode ---"
    Write-Host "host_out $hostOut"
    Write-Host "pe_out $peOut"
    if ($hostOut -ne $peOut) { throw "HOST_NATIVE_MISMATCH $Mode" }
    if ($hostOut -notmatch $Want) { throw "missing $Want in $Mode" }
    Write-Host "HOST_NATIVE_MATCH mode $Mode"
}

try {
    Run-Mode "proxy-ws" "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    Run-Mode "proxy-ws-bad" "400"
    Run-Mode "proxy-ws-refuse" "403"
    Write-Host "HOST_NATIVE_MATCH"
    Write-Host "PASS_AFTER at $AfterSha host=PE proxy-ws 101/400/403"
} finally {
    try { if (-not $up.HasExited) { $up.Kill() } } catch { }
}
Write-Host "rebuild-proxy-ws-windows ok"
exit 0
