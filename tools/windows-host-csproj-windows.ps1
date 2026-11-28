# CouchStation: build the Windows host csproj (all root *.cs, WINDOWS TFM).
# Linux cannot prove this. Caps unchanged. No Defender changes.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
Write-Output "windows_host_csproj_build start sha $((git rev-parse HEAD).Trim())"
& dotnet build (Join-Path $Root "windows\vire.windows.csproj") -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw "windows/vire.windows.csproj build exit $LASTEXITCODE" }
$dll = Join-Path $Root "windows\bin\Release\net10.0-windows\vire.dll"
if (-not (Test-Path $dll)) { throw "missing $dll" }
Write-Output "windows_host_csproj_build ok $dll"
Write-Output "PASS_AFTER windows_host_csproj_build"
exit 0
