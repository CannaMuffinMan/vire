# Runs site-pages.vire and fails unless both HTML pages were written.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

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

$index = Join-Path $Root "site/index.html"
$other = Join-Path $Root "site/other.html"
foreach ($path in @($index, $other)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

Write-Output "dotnet exec bin/Release/net10.0/vire.dll site-pages.vire"
$out = & dotnet exec $Dll "site-pages.vire" 2>&1
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Output $_ }
if ($code -ne 0) {
    Write-Error "site-pages.vire exited $code"
    exit 1
}

function Fail-Missing([string]$path, [string]$needle) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Error "missing $path"
        exit 1
    }
    $text = Get-Content -LiteralPath $path -Raw
    if ($text.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) {
        Write-Error "expected text not in $path"
        exit 1
    }
}

Fail-Missing $index "<title>Vire page proof</title>"
Fail-Missing $index "<p>This page is a Vire capability proof.</p>"
Fail-Missing $index "href=`"other.html`""
Fail-Missing $other "<title>Vire linked page</title>"
Fail-Missing $other "<p>This second page was written by the same Vire program.</p>"
Write-Output "PASS site/index.html site/other.html"
exit 0
