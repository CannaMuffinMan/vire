# CouchStation Windows PE proof for rpc-portal-go / dev-portal-go / fcgbds-dashboard-go
# JWT cookie gates, 307, 405, sandbox dist static.
# Linux ELF is proven by tools/rebuild-portal-diff.sh. This script is the PE twin.
# Prerequisites: gen1 PE compiler (compile-native.vire); loopback only.
# PE is unproven on the Linux VM that wrote this lane.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:JWT_SECRET -ErrorAction SilentlyContinue

Write-Host "1. Unset VIRE_BUDGET (do not export 5000000)."
Write-Host "2. dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo"
Write-Host "3. Copy src/http-client.vire src/rt-crypto.vire src/dist-static.vire src/portal-jwt.vire"
Write-Host "   and tests/rebuild/guests/rpc-portal-go.vire, dev-portal-go.vire, fcgbds-dashboard-go.vire"
Write-Host "   into data/native-portal/"
Write-Host "4. compile-native.vire each guest with argv pe; confirm MZ + PE32+ (optional header 0x20b)."
Write-Host "5. Confirm hmac/digest in IAT (rt_hmac / rt_digest), not LoadLibrary stubs."
Write-Host "6. Fixture JWT secret ascii 'fixture-jwt-secret'. Never production JWT_SECRET."
Write-Host "7. Host vs PE CLI: jwt-sign / jwt-verify for role=dev and type=dev_session. stdout must match."
Write-Host "8. Host vs PE listen (dist '-'): tests/rebuild/contracts/rpc-portal-go.json,"
Write-Host "   fcgbds-dashboard-go.json, dev-portal-go-auth.json. Match status and body."
Write-Host "9. With data/rebuild-dist: GET / and GET /about HTML match. GET /escape..path is 404."
Write-Host "10. Cookie header is a process arg (listen does not parse Cookie). Caps 32MB / 100000 / 5M."
Write-Host "11. Do not skip tests. Do not connect off-box. Do not use production hosts."
exit 1
