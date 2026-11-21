# CouchStation Windows PE proof for landing-go SOP HMAC cookie + loopback proxy routes.
# Linux ELF is proven by tools/rebuild-sop-proxy-diff.sh. This script is the PE twin.
# Prerequisites: gen1 PE compiler (compile-native.vire); loopback only.
# PE is unproven on the Linux VM that wrote this lane.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

Write-Host "1. Unset VIRE_BUDGET (do not export 5000000)."
Write-Host "2. dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo"
Write-Host "3. Stage src: bash is not required; copy src/http-client.vire src/rt-crypto.vire src/sop-cookie.vire"
Write-Host "   and tests/rebuild/guests/landing-sop.vire, dev-portal-go.vire, edge-go.vire into data/native-sop/"
Write-Host "4. compile-native.vire each guest with argv pe; confirm MZ + PE32+ (optional header 0x20b)."
Write-Host "5. Confirm hmac/digest in IAT path (rt_hmac / rt_digest), not LoadLibrary stubs."
Write-Host "6. Generate a fixture secret (16 random bytes hex). Never use production FCG_AUTH_COOKIE_SECRET."
Write-Host "7. Host interpreter vs PE: landing-sop modes issue / verify (ok, tamper, expired, missing) / header."
Write-Host "   stdout must match. Tamper and expired must deny."
Write-Host "8. Loopback upstream on 127.0.0.1 answering GET /echo with body up-ok."
Write-Host "9. Host vs PE listen: sop-cookie.json, sop-proxy.json, dev-portal-go.json (GET / 503, GET /api/auth/session 307 without page cookie; 503 not_configured with page cookie arg), edge-go www + unknown Host."
Write-Host "   Match status, contract headers, body. Caps stay 32MB / 100000 / 5M."
Write-Host "10. Do not skip tests. Do not connect off-box."
exit 1
