# Host interpreter vs gen1 native PE for AES-256-GCM KATs.
# CouchStation / Windows PE run. Does not raise 32MB arena, 100000 list cap, or 5M steps.
# Does not claim a PE run on Linux.
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

$TableSha = if ($env:AES_GCM_FAIL_BEFORE_SHA) { $env:AES_GCM_FAIL_BEFORE_SHA } else { "04ea5186c6ed3ce35451df318e29a1db9b9eabe8" }
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $TableSha"
Write-Output "pass_after_sha $AfterSha"
$BeforeSrc = git show "${TableSha}:src/rt-aes.vire"
if ($BeforeSrc -notmatch "sbox at") { throw "FAIL_BEFORE expected table lookup at $TableSha" }
if ($BeforeSrc -notmatch "if d >= 256") { throw "FAIL_BEFORE expected xtime branch at $TableSha" }
if ($BeforeSrc -notmatch "if flag == 1") { throw "FAIL_BEFORE expected GHASH bit skip at $TableSha" }
Write-Output "FAIL_BEFORE at ${TableSha}: S-box table lookup, xtime branch, GHASH bit skip present"

Write-Output "aes_gcm_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostOut = & dotnet exec $VireDll aes-gcm-prove.vire
$code = $LASTEXITCODE
$sw.Stop()
Write-Output $hostOut
Write-Output "aes_gcm_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "aes_gcm_host_exit $code"
if ($code -ne 0) { throw "host aes-gcm-prove exit $code" }
if ("$hostOut" -notmatch "AES-GCM PROVE pass") { throw "host aes-gcm-prove missing pass" }
if ("$hostOut" -notmatch "530f8afbc74536b9a963b4f1c4cb738b") { throw "missing NIST empty tag" }
if ("$hostOut" -notmatch "WYCHEPROOF tag-tamper REJECT") { throw "missing tag-tamper" }
if ("$hostOut" -notmatch "WYCHEPROOF aad-tamper REJECT") { throw "missing aad-tamper" }
if ("$hostOut" -notmatch "WYCHEPROOF truncated-tag REJECT") { throw "missing truncated-tag" }
if ("$hostOut" -notmatch "no-plaintext PASS") { throw "missing no-plaintext" }

$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$lib = Get-Content -Raw (Join-Path $Root "src/rt-aes.vire")
$prove = Get-Content -Raw (Join-Path $Root "aes-gcm-prove.vire")
$prove = $prove -replace '(?m)^use "src/rt-aes.vire"\s*', ''
Set-Content -Path (Join-Path $Data "aes-gcm-prove.vire") -Value ($lib + "`n" + $prove) -NoNewline
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$hexRel = "data/aes-gcm-prove.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$compileOut = & dotnet exec $VireDll --compiler compile-native.vire data/aes-gcm-prove.vire $hexRel
$compileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $compileOut
Write-Output "aes_gcm_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "aes_gcm_pe_compile_exit $compileCode"
if ($compileCode -ne 0) { throw "compile-native aes-gcm-prove exit $compileCode" }
if ("$compileOut" -notmatch "compiled") { throw "compile-native missing compiled" }

$exe = Join-Path $Data "aes-gcm-prove.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peOut = & $exe
$peCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peOut
Write-Output "aes_gcm_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "aes_gcm_pe_exit $peCode"
if ($peCode -ne 0) { throw "aes-gcm PE exit $peCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
$peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE stdout differ"
}
$AfterSrc = Get-Content -Raw (Join-Path $Root "src/rt-aes.vire")
if ($AfterSrc -match "sbox at") { throw "PASS_AFTER still has sbox at" }
if ($AfterSrc -match "if flag == 1") { throw "PASS_AFTER still has GHASH skip" }
Write-Output "PASS_AFTER at $AfterSha host and gen1 PE AES-GCM outputs identical; no secret sbox index / GHASH skip in source"
Write-Output "aes gcm windows prove ok"
