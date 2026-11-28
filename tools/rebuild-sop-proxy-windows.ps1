# CouchStation PE: landing-sop issue/verify/header plus listen /healthz vs host.
# Linux ELF: tools/rebuild-sop-proxy-diff.sh. Do not claim PE proof from Linux.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "223b4ef302e6ca3ca7677117e4af147541c05a30"
Write-Host "FAIL_BEFORE at $FailBefore sop-fail.vire not gated / not proxied"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}

$stage = Join-Path $Root "data/native-sop-pe"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Root "src/rt-crypto.vire") (Join-Path $stage "rt-crypto.vire") -Force
Copy-Item (Join-Path $Root "src/sop-cookie.vire") (Join-Path $stage "sop-cookie.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/landing-sop.vire") (Join-Path $stage "landing-sop.vire") -Force
$fail = & dotnet exec $VireDll (Join-Path $Root "tests/rebuild/guests/sop-fail.vire") | Out-String
if ($fail -notmatch "not gated") { throw "fail-before missing not gated" }
if ($fail -notmatch "not proxied") { throw "fail-before missing not proxied" }
Write-Host "FAIL_BEFORE at $FailBefore (sop-fail.vire)"

$hex = Join-Path $stage "landing-sop.hex"
$exe = Join-Path $stage "landing-sop.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
& dotnet exec $VireDll --compiler compile-native.vire data/native-sop-pe/landing-sop.vire data/native-sop-pe/landing-sop.hex pe
if ($LASTEXITCODE -ne 0) { throw "compile exit $LASTEXITCODE" }
$hexText = (Get-Content -Raw $hex).Trim()
$pe = New-Object byte[] ($hexText.Length / 2)
for ($i = 0; $i -lt $pe.Length; $i++) { $pe[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16) }
[IO.File]::WriteAllBytes($exe, $pe)

$Secret = -join ((1..16) | ForEach-Object { "{0:x2}" -f (Get-Random -Maximum 256) })
$Now = "1000"
$ExpOk = "2000"
function Pair([string]$Needle, [string[]]$Argv) {
    $hostOut = & dotnet exec $VireDll data/native-sop-pe/landing-sop.vire @Argv | Out-String
    $peOut = & $exe @Argv | Out-String
    if ($hostOut -ne $peOut) { throw "HOST_NATIVE_MISMATCH $Needle`nhost $hostOut`npe $peOut" }
    if ($hostOut -notmatch $Needle) { throw "missing $Needle" }
    Write-Host "HOST_NATIVE_MATCH $Needle"
    return $hostOut
}
$issued = Pair "ok" @($Secret, "0", $Now, "issue", $ExpOk)
$cookie = ($issued -split "`n" | Where-Object { $_ -match "^v1\." } | Select-Object -First 1).Trim()
if (-not $cookie) { throw "cookie missing v1. prefix" }
Pair "^ok" @($Secret, "0", $Now, "verify", $cookie, $Now) | Out-Null
Pair "tamper" @($Secret, "0", $Now, "verify", ($cookie + "00"), $Now) | Out-Null
Pair "expired" @($Secret, "0", $Now, "verify", $cookie, "9000") | Out-Null
Pair "missing" @($Secret, "0", $Now, "verify", "-", $Now) | Out-Null
$hdr = "Cookie:fcg_sop_authenticated=$cookie"
Pair "^ok" @($Secret, "0", $Now, "header", $hdr, $Now) | Out-Null

$hostProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-sop-pe/landing-sop.vire", $Secret, "0", $Now) -WorkingDirectory $Root
$peProc = Start-VireProcess -FilePath $exe -ArgumentList @($Secret, "0", $Now) -WorkingDirectory $Root
try {
    $hp = Get-ListenPort $hostProc
    $np = Get-ListenPort $peProc
    $hh = Invoke-VireHttpRequest -Port $hp -Method "GET" -Path "/healthz"
    $ph = Invoke-VireHttpRequest -Port $np -Method "GET" -Path "/healthz"
    if ($hh.Body.Trim() -ne "ok" -or $ph.Body.Trim() -ne "ok") { throw "healthz mismatch $($hh.Body)/$($ph.Body)" }
    Write-Host "HOST_NATIVE_MATCH listen GET /healthz"
    Write-Host "PASS_AFTER at $AfterSha"
} finally {
    try { $hostProc.Kill() } catch { }
    try { $peProc.Kill() } catch { }
}
Write-Host "rebuild-sop-proxy-windows ok"
exit 0
