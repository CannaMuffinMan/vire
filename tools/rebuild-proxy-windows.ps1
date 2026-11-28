# CouchStation PE: host-vs-PE proxy modes vs loopback http-echo (not MZ-only).
# Linux ELF: tools/rebuild-proxy-diff.sh. This Linux agent cannot claim PE proof.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "4682595ee586c7440d06bdc2979b8b7e2c94812d"
Write-Host "FAIL_BEFORE at $FailBefore proxy-fail.vire not proxied"
Write-Host "PASS_AFTER expect $AfterSha"

$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
$ProofDll = Get-VireProofDll
$stage = Join-Path $Root "data/native-proxy-pe"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $stage "http-client.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/proxy-http.vire") (Join-Path $stage "proxy-http.vire") -Force
$hex = Join-Path $stage "proxy-http.hex"
$exe = Join-Path $stage "proxy-http.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
& dotnet exec $VireDll --compiler compile-native.vire data/native-proxy-pe/proxy-http.vire data/native-proxy-pe/proxy-http.hex pe
if ($LASTEXITCODE -ne 0) { throw "compile exit $LASTEXITCODE" }
$hexText = (Get-Content -Raw $hex).Trim()
$pe = New-Object byte[] ($hexText.Length / 2)
for ($i = 0; $i -lt $pe.Length; $i++) { $pe[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16) }
[IO.File]::WriteAllBytes($exe, $pe)
if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "PE missing MZ" }

$fail = & dotnet exec $VireDll (Join-Path $Root "tests/rebuild/guests/proxy-fail.vire") | Out-String
if ($fail -match "echo-get") { throw "FAIL_BEFORE unexpectedly proxied" }
Write-Host "FAIL_BEFORE at $FailBefore not proxied"

$up = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "http-echo") -WorkingDirectory $Root
$upPort = Get-ListenPort $up
Write-Host "upstream 127.0.0.1:$upPort"

function Run-Mode([string]$Mode, [string]$Want) {
    $hostOut = & dotnet exec $VireDll data/native-proxy-pe/proxy-http.vire "$upPort" $Mode | Out-String
    $peOut = & $exe "$upPort" $Mode | Out-String
    Write-Host "--- mode $Mode ---"
    Write-Host "host_out $hostOut"
    Write-Host "pe_out $peOut"
    if ($hostOut -ne $peOut) { throw "HOST_NATIVE_MISMATCH $Mode" }
    if ($Want -and ($hostOut -notmatch [regex]::Escape($Want)) -and ($hostOut -notmatch $Want)) { throw "missing $Want in $Mode" }
    Write-Host "HOST_NATIVE_MATCH mode $Mode"
}

try {
    Run-Mode "client-get" "echo-get"
    Run-Mode "client-post" "echo-post:hi-body"
    Run-Mode "client-chunk" "te"
    Run-Mode "client-clte" "cl-te"
    Run-Mode "client-dupcl" "dup-cl"
    Run-Mode "client-oversize" "cl"
    Run-Mode "proxy-get" "echo-get"
    Run-Mode "proxy-post" "echo-post:from-proxy"
    Run-Mode "proxy-loc" "/app/sop"
    Run-Mode "proxy-fail" "bad gateway"
    Run-Mode "proxy-smuggle" "bad gateway"
    Write-Host "HOST_NATIVE_MATCH"
    Write-Host "PASS_AFTER at $AfterSha host=PE proxy modes"
} finally {
    try { if (-not $up.HasExited) { $up.Kill() } } catch { }
}
Write-Host "rebuild-proxy-windows ok"
exit 0
