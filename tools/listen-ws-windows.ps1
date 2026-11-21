# CouchStation Windows PE proof: listen-side RFC 6455 Upgrade hijack.
# Linux ELF is proven by tools/rebuild-listen-ws-diff.sh (and wss by rebuild-listen-wss-diff.sh).
# This Linux agent cannot execute PE. Do not claim PE proof from this run.
# Native Windows PE tls_listen stays fail-closed until SChannel is proven.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "a64cfe5fdb398ac7c8049bd41ac431d780a0b09e"
Write-Host ("FAIL_BEFORE at " + $FailBefore + ": packed ELF accepted GET /ws/refuse with 101")
Write-Host ("PASS_AFTER expect " + $AfterSha)

$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000"

Write-Host "listen-ws-windows: compile tests/rebuild/guests/listen-ws.vire with compile-native.vire"
Write-Host "Check PE MZ; ws2_32 connect/send/recv. Loopback 127.0.0.1 only."
Write-Host "Stand up the RFC 6455 echo fixture from tools/rebuild-listen-ws-diff.sh."
Write-Host "Host interpreter vs PE, identical transcripts:"
Write-Host "  GET /ws/echo Upgrade: websocket -> 101, Accept s3pPLMBiTxaQ9kYGzzhZRbK+xOo=, echo hex 81026869"
Write-Host "  Upgrade: h2c -> 400"
Write-Host "  GET /ws/refuse -> 403"
Write-Host "Do not skip tests. Caps stay 32MB / 100000 / 5M. No external network."
Write-Host "Fill PASS_AFTER PE hashes here after the CouchStation run."
Write-Host "This script was not executed as PE on Linux."
exit 1
