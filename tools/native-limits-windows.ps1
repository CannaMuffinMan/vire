# FAIL_BEFORE / PASS_AFTER for native implementation limits. Real PE on Windows.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$BaseSha = (git rev-parse origin/native-compiler).Trim()
$AfterSha = (git rev-parse HEAD).Trim()
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $Root "tests/native/deep-expr.vire") (Join-Path $Data "deep-expr.vire") -Force
Copy-Item (Join-Path $Root "tests/native/million-hash.vire") (Join-Path $Data "million-hash.vire") -Force
Copy-Item (Join-Path $Root "tests/native/long-ascii.vire") (Join-Path $Data "long-ascii.vire") -Force

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

git show "${BaseSha}:compile-native.vire" | Set-Content -Path (Join-Path $Root "compile-native.base.vire") -Encoding utf8
$before = & dotnet exec $VireDll compile-native.base.vire data/deep-expr.vire data/deep-expr.base.hex 2>&1 | Out-String
Write-Output $before
if ($before -notmatch "definitions called too deeply") {
    throw "expected base parser MaxCalls miss"
}
Write-Output ("FAIL_BEFORE at " + $BaseSha + ": compile-native parseExpr MaxCalls 64 nested (1+(1+…)) depth 20 → definitions called too deeply")

function Invoke-HostPe([string]$Name, [string]$WantContains) {
    $srcRel = "data/$Name.vire"
    $hostOut = & dotnet exec $VireDll $srcRel
    $hostCode = $LASTEXITCODE
    Write-Output $hostOut
    if ($hostCode -ne 0) { throw "host $Name exit $hostCode" }
    $comp = & dotnet exec $VireDll --compiler compile-native.vire $srcRel "data/$Name.hex"
    Write-Output $comp
    if ($LASTEXITCODE -ne 0) { throw "compile $Name exit $LASTEXITCODE" }
    if ("$comp" -notmatch "compiled") { throw "compile $Name missing compiled" }
    $exe = Join-Path $Data "$Name.exe"
    Convert-HexToExe (Join-Path $Root "data/$Name.hex") $exe
    $peOut = & $exe
    $peCode = $LASTEXITCODE
    Write-Output $peOut
    if ($peCode -ne 0) { throw "PE $Name exit $peCode" }
    $hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
    $peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
    if ($hostNorm -ne $peNorm) { throw "host and PE stdout differ for $Name" }
    if ($WantContains -and ($hostNorm -notmatch $WantContains)) { throw "$Name missing $WantContains" }
    Write-Output "host_pe_match $Name"
}

Invoke-HostPe "deep-expr" "^21$"
Invoke-HostPe "million-hash" "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
Invoke-HostPe "long-ascii" "^4096$"

Write-Output ("PASS_AFTER at " + $AfterSha + ": host and gen1 PE identical for deep-expr, FIPS 1M SHA, 4096-char ASCII literal")
Write-Output "native limits windows check ok"
Remove-Item -Force (Join-Path $Root "compile-native.base.vire") -ErrorAction SilentlyContinue
