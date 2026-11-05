# Loads deps/textkit and deps/listkit through need, then proves a missing package fails.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"

$Dll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path -LiteralPath $Dll)) {
    Write-Output "building Release"
    & dotnet build -c Release --nologo
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
if (-not (Test-Path -LiteralPath $Dll)) {
    Write-Error "missing $Dll"
    exit 1
}

$want = "alpha beta hi 3 y"
Write-Output "dotnet exec bin/Release/net10.0/vire.dll samples/deps-demo.vire"
$out = & dotnet exec $Dll "samples/deps-demo.vire" 2>&1
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Output $_ }
if ($code -ne 0) {
    Write-Error "deps-demo exited $code"
    exit 1
}
$line = ($out | ForEach-Object { $_.ToString() } | Where-Object { $_ -eq $want } | Select-Object -Last 1)
if ($line -ne $want) {
    Write-Error "expected '$want'"
    exit 1
}

Write-Output "dotnet exec bin/Release/net10.0/vire.dll samples/deps-missing.vire"
$miss = & dotnet exec $Dll "samples/deps-missing.vire" 2>&1
$missCode = $LASTEXITCODE
$miss | ForEach-Object { Write-Output $_ }
if ($missCode -eq 0) {
    Write-Error "missing package should fail"
    exit 1
}
Write-Output "deps-lib ok"
exit 0
