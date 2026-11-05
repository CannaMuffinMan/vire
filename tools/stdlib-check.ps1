# Loads jsonkit, filekit, and numkit through need, then proves a missing package fails.
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

$want = "[1,2,3] stdlib 2 3 8 15"
$blocked = Join-Path $Root "samples/site/stdlib-should-not.txt"
if (Test-Path -LiteralPath $blocked) { Remove-Item -LiteralPath $blocked -Force }

Write-Output "dotnet exec bin/Release/net10.0/vire.dll samples/stdlib-demo.vire"
$out = & dotnet exec $Dll "samples/stdlib-demo.vire" 2>&1
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Output $_ }
if ($code -ne 0) {
    Write-Error "stdlib-demo exited $code"
    exit 1
}
$line = ($out | ForEach-Object { $_.ToString() } | Where-Object { $_ -eq $want } | Select-Object -Last 1)
if ($line -ne $want) {
    Write-Error "expected '$want'"
    exit 1
}
if (Test-Path -LiteralPath $blocked) {
    Write-Error "filekit wrote outside data/"
    exit 1
}
$saved = Join-Path $Root "samples/data/stdlib-demo.json"
if (-not (Test-Path -LiteralPath $saved)) {
    Write-Error "filekit did not write under data/"
    exit 1
}
Remove-Item -LiteralPath $saved -Force
$savedDir = Split-Path -Parent $saved
if ((Get-ChildItem -LiteralPath $savedDir -Force | Measure-Object).Count -eq 0) {
    Remove-Item -LiteralPath $savedDir -Force
}

Write-Output "dotnet exec bin/Release/net10.0/vire.dll samples/deps-missing.vire"
$miss = & dotnet exec $Dll "samples/deps-missing.vire" 2>&1
$missCode = $LASTEXITCODE
$miss | ForEach-Object { Write-Output $_ }
if ($missCode -eq 0) {
    Write-Error "missing package should fail"
    exit 1
}
Write-Output "stdlib ok"
exit 0
