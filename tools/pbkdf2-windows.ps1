$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

$baseSha = "d095972ed61474e8e852e391b984e4221dfe6c8f"
$baseCrypto = git -C $Root show "${baseSha}:src/rt-crypto.vire"
if ($baseCrypto -match "pbkdf2_sha256") { throw "base rt-crypto already has pbkdf2" }
Write-Output "FAIL_BEFORE at ${baseSha}: RFC 7914 section 11 PBKDF2-HMAC-SHA256 is absent (no pbkdf2_sha256 on HMAC-SHA256 session primitives)"

Write-Output "pbkdf2_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostOut = & dotnet exec $VireDll pbkdf2-prove.vire
$code = $LASTEXITCODE
$sw.Stop()
Write-Output $hostOut
Write-Output "pbkdf2_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "pbkdf2_host_exit $code"
if ($code -ne 0) { throw "host pbkdf2-prove exit $code" }
if ("$hostOut" -notmatch "PBKDF2 PROVE pass") { throw "host pbkdf2-prove missing pass" }
if ("$hostOut" -notmatch "RFC7914 11 c=1 PASS") { throw "missing RFC7914 c=1" }
if ("$hostOut" -notmatch "RFC6070-SHA256 c=4096 PASS") { throw "missing RFC6070 c=4096" }
if ("$hostOut" -notmatch "RFC7914 11 c=80000 PASS") { throw "missing RFC7914 c=80000" }

$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item -Force (Join-Path $Root "src/rt-crypto.vire") (Join-Path $Root "data/src/rt-crypto.vire")
Copy-Item -Force (Join-Path $Root "pbkdf2-prove.vire") (Join-Path $Data "pbkdf2-prove.vire")
$hexRel = "data/pbkdf2-prove.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$compileOut = & dotnet exec $VireDll --compiler compile-native.vire data/pbkdf2-prove.vire $hexRel
$compileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $compileOut
Write-Output "pbkdf2_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "pbkdf2_pe_compile_exit $compileCode"
if ($compileCode -ne 0) { throw "compile-native pbkdf2-prove exit $compileCode" }
if ("$compileOut" -notmatch "compiled") { throw "compile-native missing compiled" }

$exe = Join-Path $Data "pbkdf2-prove.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peOut = & $exe
$peCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peOut
Write-Output "pbkdf2_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "pbkdf2_pe_exit $peCode"
if ($peCode -ne 0) { throw "pbkdf2 PE exit $peCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r','').Trim()
$peNorm = (($peOut | Out-String) -replace '\r','').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE pbkdf2 stdout differ"
}
Write-Output "PASS_AFTER host and gen1 PE RFC 7914 c=1 and c=80000 match"
Write-Output "caps unchanged: arena 32MB / list 100000 / steps 5M / while 1M"
Write-Output "pbkdf2 windows prove ok"
