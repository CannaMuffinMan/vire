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

Write-Output "crypto_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostOut = & dotnet exec $VireDll crypto-prove.vire
$code = $LASTEXITCODE
$sw.Stop()
Write-Output $hostOut
Write-Output "crypto_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "crypto_host_exit $code"
if ($code -ne 0) { throw "host crypto-prove exit $code" }
if ("$hostOut" -notmatch "CRYPTO PROVE pass") { throw "host crypto-prove missing pass" }

$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$lib = Get-Content -Raw (Join-Path $Root "src/rt-crypto.vire")
$prove = Get-Content -Raw (Join-Path $Root "crypto-prove.vire")
$prove = $prove -replace '(?m)^use "src/rt-crypto.vire"\s*', ''
Set-Content -Path (Join-Path $Data "crypto-prove.vire") -Value ($lib + "`n" + $prove) -NoNewline
$hexRel = "data/crypto-prove.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$compileOut = & dotnet exec $VireDll compile-native.vire data/crypto-prove.vire $hexRel
$compileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $compileOut
Write-Output "crypto_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "crypto_pe_compile_exit $compileCode"
if ($compileCode -ne 0) { throw "compile-native crypto-prove exit $compileCode" }
if ("$compileOut" -notmatch "compiled") { throw "compile-native missing compiled" }

$exe = Join-Path $Data "crypto-prove.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peOut = & $exe
$peCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peOut
Write-Output "crypto_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "crypto_pe_exit $peCode"
if ($peCode -ne 0) { throw "crypto PE exit $peCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r','').Trim()
$peNorm = (($peOut | Out-String) -replace '\r','').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE stdout differ"
}
Write-Output "crypto host pe match"
Write-Output "crypto windows prove ok"
