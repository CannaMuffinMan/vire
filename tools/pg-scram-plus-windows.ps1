# CouchStation: host RFC 7677 / SCRAM-SHA-256-PLUS guest prove. Not PE execute proof.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
Write-Output "pg_scram_plus_windows_host_start"
$hostOut = & dotnet exec $VireDll pg-scram-plus-prove.vire
$code = $LASTEXITCODE
Write-Output $hostOut
Write-Output "pg_scram_plus_windows_exit $code"
if ($code -ne 0) { throw "host pg-scram-plus-prove exit $code" }
if ("$hostOut" -notmatch "PG SCRAM PLUS PROVE pass") { throw "host plus prove missing pass" }
if ("$hostOut" -notmatch "PLUS client-final p PASS") { throw "host plus prove missing client-final" }
if ("$hostOut" -notmatch "tls plus no bind REJECT") { throw "host plus prove missing tls fail-closed" }
if ("$hostOut" -notmatch "empty leaf der PASS") { throw "host plus prove missing empty-leaf" }
Write-Output "Linux ELF/Unicorn is not Windows PE proof. This script is host interpreter only."
Write-Output "pg_scram_plus_windows pass"
