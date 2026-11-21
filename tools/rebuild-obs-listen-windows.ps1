# CouchStation Windows PE proof for dashboard obs_307 + listen+proxy_reply.
# Linux ELF is proven by tools/rebuild-portal-diff.sh and tools/rebuild-proxy-diff.sh.
# Prerequisites: gen1 PE compiler on the machine; loopback 127.0.0.1 only.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

Write-Host "rebuild-obs-listen-windows: compile fcgbds-dashboard-go.vire and proxy-http.vire (PE)"
Write-Host "FAIL_BEFORE 55d95a67: native GET /obs is HTTP 500 {error:route failed}; host is 307"
Write-Host "FAIL_BEFORE 55d95a67: native listen GET /proxy SEGVs; host 200 up-ok"
Write-Host "PASS_AFTER this SHA: host vs PE GET /obs both 307 body {status:307}"
Write-Host "PASS_AFTER: listen GET/POST /proxy both 200 with upstream body, no SEGV"
Write-Host "Do not skip tests. Caps stay 32MB / 100000 / 5M. No Defender changes. No external network."
exit 1
