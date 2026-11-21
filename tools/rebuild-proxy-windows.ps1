# CouchStation Windows PE proof for loopback HTTP/1.1 client + reverse-proxy.
# Linux ELF is proven by tools/rebuild-proxy-diff.sh. This script is the PE twin.
# Prerequisites: gen1 PE compiler (compile-native.vire) on the machine; loopback only.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

Write-Host "rebuild-proxy-windows: compile tests/rebuild/guests/proxy-http.vire with compile-native.vire"
Write-Host "Check PE MZ, ws2_32 connect/send/recv/setsockopt IAT (not stubs)"
Write-Host "Stand up a 127.0.0.1 upstream that answers /echo /chunk /clte /dupcl /oversize /hang /redir"
Write-Host "Run host interpreter vs PE for modes: client-get, client-post, client-chunk, client-clte,"
Write-Host "  client-dupcl, client-oversize, client-timeout, proxy-get, proxy-post, proxy-loc,"
Write-Host "  proxy-fail, proxy-smuggle"
Write-Host "Then listen + GET/POST /proxy (proxy_reply) host vs PE; require 200 up-ok / posted body"
Write-Host "Require identical stdout (status/body/error needles) and 502 {error:bad gateway} on fail"
Write-Host "Do not skip tests. Caps stay 32MB / 100000 / 5M. No external network."
exit 1
