# CouchStation PE: compile apigo-ws and match host 101/echo on loopback.
# Linux ELF: tools/apigo-ws-linux.sh. Do not claim PE proof from Linux.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
$ProofDll = Get-VireProofDll
$stage = Join-Path $Root "data/apigo-ws-pe"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Root "tests/rebuild/guests/apigo-ws.vire") (Join-Path $stage "apigo-ws.vire") -Force
$hex = Join-Path $stage "apigo-ws.hex"
$exe = Join-Path $stage "apigo-ws.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
& dotnet exec $VireDll --compiler compile-native.vire data/apigo-ws-pe/apigo-ws.vire data/apigo-ws-pe/apigo-ws.hex pe
if ($LASTEXITCODE -ne 0) { throw "compile exit $LASTEXITCODE" }
$hexText = (Get-Content -Raw $hex).Trim()
$pe = New-Object byte[] ($hexText.Length / 2)
for ($i = 0; $i -lt $pe.Length; $i++) { $pe[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16) }
[IO.File]::WriteAllBytes($exe, $pe)

$hostProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/apigo-ws-pe/apigo-ws.vire") -WorkingDirectory $Root
$peProc = Start-VireProcess -FilePath $exe -WorkingDirectory $Root
try {
    $hp = Get-ListenPort $hostProc
    $np = Get-ListenPort $peProc
    $hh = Invoke-VireHttpRequest -Port $hp -Method "GET" -Path "/health"
    $ph = Invoke-VireHttpRequest -Port $np -Method "GET" -Path "/health"
    if ($hh.Body -notmatch "ok" -or $ph.Body -notmatch "ok") { throw "health mismatch" }
    & dotnet exec $ProofDll ws-prove $hp
    if ($LASTEXITCODE -ne 0) { throw "host ws-prove exit $LASTEXITCODE" }
    & dotnet exec $ProofDll ws-prove $np
    if ($LASTEXITCODE -ne 0) { throw "PE ws-prove exit $LASTEXITCODE" }
    Write-Host "HOST_NATIVE_MATCH apigo-ws 101/echo"
    Write-Host "PASS_AFTER at $((git rev-parse HEAD).Trim())"
} finally {
    try { $hostProc.Kill() } catch { }
    try { $peProc.Kill() } catch { }
}
Write-Host "apigo-ws-windows ok"
exit 0
