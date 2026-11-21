# CouchStation Windows PE proof: RFC 6455 upgrade through the reverse-proxy primitive.
# Linux ELF is proven by tools/rebuild-proxy-ws-diff.sh. This script is the PE twin.
# Prerequisites: gen1 PE compiler (compile-native.vire) on the machine; loopback only.
# Do not claim this Linux agent ran PE. Caps stay 32MB / 100000 / 5M. No Defender changes.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "cec3896320411cccdc016f59fedd1114ffb823e3"
Write-Host ("FAIL_BEFORE at " + $FailBefore + ": PR #107 http-client strips Upgrade/Connection; handshake cannot 101")
Write-Host ("PASS_AFTER expect " + $AfterSha)

$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000"

Write-Host "rebuild-proxy-ws-windows: compile tests/rebuild/guests/proxy-http.vire with compile-native.vire"
Write-Host "Check PE MZ; ws2_32 connect/send/recv (same IAT as HTTP proxy). Loopback 127.0.0.1 only."
Write-Host "Stand up a 127.0.0.1 RFC 6455 echo fixture (see tools/rebuild-proxy-ws-diff.sh)."
Write-Host "FAIL_BEFORE: restore http-client.vire from $FailBefore; mode proxy-ws must not print 101 or 81026869."
Write-Host "PASS_AFTER host interpreter vs PE, identical stdout:"
Write-Host "  proxy-ws -> 101, Sec-WebSocket-Accept s3pPLMBiTxaQ9kYGzzhZRbK+xOo=, tunnel hex 810268698800"
Write-Host "  proxy-ws-bad -> 400 {error:bad request}"
Write-Host "  proxy-ws-refuse -> 403 forbidden"
Write-Host "  proxy-get still echo-get (hop-by-hop strip unchanged)"
Write-Host "Do not skip tests. Caps stay 32MB / 100000 / 5M. No external network."
Write-Host "Fill PASS_AFTER PE hashes here after the CouchStation run."
exit 1
