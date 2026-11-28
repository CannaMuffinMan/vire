# CouchStation PE proof for FCG /payments /mine /chain /block.
# Linux ELF proof is tools/rebuild-health-diff.sh and tools/rebuild-chain-diff.sh.
# This script is the Windows steps only. Do not treat a Linux run as PE proof.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing gen1.exe; run native-selfhost-handoff.ps1 first" }

function Compile-Guest([string]$Src, [string]$Stem) {
    $vire = Get-Content -Raw -LiteralPath $Src
    $vire = $vire.Replace("listen with 18080", "listen with 0")
    $outSrc = Join-Path $Data "$Stem.vire"
    Set-Content -LiteralPath $outSrc -Value $vire -NoNewline
    $hex = Join-Path $Data "$Stem.hex"
    $exe = Join-Path $Data "$Stem.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    $p = Start-Process -FilePath $gen1 -ArgumentList @("data/$Stem.vire", "data/$Stem.hex") -WorkingDirectory $Root -NoNewWindow -PassThru
    $code = Get-ChildExitCode $p
    if ($code -ne 0) { throw "gen1 $Stem compile exit $code" }
    Convert-HexToExe $hex $exe
    return $exe
}

$BlockTok = "test-block-token1"
$env:FCG_BLOCK_TOKEN = $BlockTok
$Bearer = "Bearer $BlockTok"

function Read-Http([int]$Port, [string]$Method, [string]$Path, [string]$Send, [string]$Authorization) {
    return Invoke-VireHttpRequest -Port $Port -Method $Method -Path $Path -Send $Send -Authorization $Authorization
}

function Assert-Case($got, $wantStatus, $wantBody, $name) {
    if ($got.Status -ne $wantStatus -or $got.Body -ne $wantBody) {
        throw "$name got $($got.Status) $($got.Body) want $wantStatus $wantBody"
    }
    Write-Host "case $name status $($got.Status) body $($got.Body)"
}

Write-Host "CouchStation PE: compile guest-health.vire and guest-chain.vire with gen1.exe"
$healthExe = Compile-Guest (Join-Path $Root "guest-health.vire") "rebuild-health-pe"
$chainExe = Compile-Guest (Join-Path $Root "guest-chain.vire") "rebuild-chain-pe"

New-Item -ItemType Directory -Force -Path (Join-Path $Data "chain") | Out-Null
Copy-Item (Join-Path $Root "data/rebuild/chain/head.json") (Join-Path $Data "chain/head.json") -Force
Copy-Item (Join-Path $Root "data/rebuild/chain/000001.json") (Join-Path $Data "chain/000001.json") -Force

$hp = Start-Process -FilePath $healthExe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput (Join-Path $Data "rebuild-health-pe.out") -PassThru
Start-Sleep -Milliseconds 400
$hout = Get-Content -Raw (Join-Path $Data "rebuild-health-pe.out")
if ($hout -notmatch "listening on 127.0.0.1:(\d+)") { Stop-Process -ErrorAction SilentlyContinue -Id $hp.Id -Force; throw "health PE did not listen" }
$hport = [int]$Matches[1]
try {
    Assert-Case (Read-Http $hport "GET" "/payments" $null) 403 '{"ok":false,"status":403,"error":"payments are off"}' "get_payments"
    Assert-Case (Read-Http $hport "GET" "/mine" $null) 403 '{"ok":false,"status":403,"error":"mining stays inside the app"}' "get_mine"
} finally {
    Stop-Process -ErrorAction SilentlyContinue -Id $hp.Id -Force
}

$cp = Start-Process -FilePath $chainExe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput (Join-Path $Data "rebuild-chain-pe.out") -PassThru
Start-Sleep -Milliseconds 400
$cout = Get-Content -Raw (Join-Path $Data "rebuild-chain-pe.out")
if ($cout -notmatch "listening on 127.0.0.1:(\d+)") { Stop-Process -ErrorAction SilentlyContinue -Id $cp.Id -Force; throw "chain PE did not listen" }
$cport = [int]$Matches[1]
try {
    Assert-Case (Read-Http $cport "GET" "/chain" $null) 200 '[{"index":0,"previous":"0","proof":"a9df21e6e7672bdb9cea28047aa39ba0fa96d54ae0791a9bab30078f5a2d4fad","text":""}]' "get_chain_genesis"
    Assert-Case (Read-Http $cport "POST" "/block" "not-json") 401 '{"error":"unauthorized"}' "post_block_unauth"
    Assert-Case (Read-Http $cport "POST" "/block" "not-json" $Bearer) 400 '{"ok":false,"status":400,"error":"bad block"}' "post_block_not_json"
    Copy-Item (Join-Path $Root "data/rebuild/chain/head.json") (Join-Path $Data "chain/head.json") -Force
    Copy-Item (Join-Path $Root "data/rebuild/chain/000001.json") (Join-Path $Data "chain/000001.json") -Force
    Assert-Case (Read-Http $cport "POST" "/block" '{"text":"fixture-one"}' $Bearer) 200 '{"ok":true,"accepted":true,"index":1,"proof":"52d7f3a9d3dfa0458a20ff820cab94c1df2acea128dacd450a6e45456c27f561"}' "post_block_accept_fixture_one"
    Copy-Item (Join-Path $Root "data/rebuild/chain/head.json") (Join-Path $Data "chain/head.json") -Force
    Copy-Item (Join-Path $Root "data/rebuild/chain/000001.json") (Join-Path $Data "chain/000001.json") -Force
    Assert-Case (Read-Http $cport "POST" "/block" '{"text":"x","previousHash":"not-the-tip"}' $Bearer) 400 '{"ok":false,"status":400,"error":"previous does not match"}' "post_block_previousHash_mismatch"
    Assert-Case (Read-Http $cport "POST" "/block" '{"text":"x","hash":"deadbeef"}' $Bearer) 400 '{"ok":false,"status":400,"error":"proof does not match"}' "post_block_hash_alias_mismatch"
    Copy-Item (Join-Path $Root "data/rebuild/chain/head.json") (Join-Path $Data "chain/head.json") -Force
    Copy-Item (Join-Path $Root "data/rebuild/chain/000001.json") (Join-Path $Data "chain/000001.json") -Force
    $keep = Read-Http $cport "POST" "/block" '{"text":"keep"}' $Bearer
    if ($keep.Status -ne 200) { throw "tamper setup $($keep.Status) $($keep.Body)" }
    $seg = Join-Path $Data "chain/000001.json"
    $raw = [System.IO.File]::ReadAllText($seg)
    [System.IO.File]::WriteAllText($seg, $raw.Replace("keep", "tamper"))
    Assert-Case (Read-Http $cport "POST" "/block" '{"text":"more"}' $Bearer) 503 '{"ok":false,"status":503,"error":"chain invalid"}' "post_block_tamper_503"
    Write-Host "PE remainder rotate/507/migrate/concurrent: run Linux tools/rebuild-chain-diff.sh; this script does not fill 512 KB segments."
} finally {
    Stop-Process -ErrorAction SilentlyContinue -Id $cp.Id -Force
}

Write-Host "CouchStation PE: unauth sidecar guests (rpc-portal-go, edge-go, dev-portal-go, fcgbds-dashboard-go)"
function Assert-GuestGet([string]$Src, [string]$Stem, [string]$Path, [int]$WantStatus, [string]$WantBody, [string]$Name) {
    $exe = Compile-Guest $Src $Stem
    $out = Join-Path $Data "$Stem.out"
    $p = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput $out -PassThru
    Start-Sleep -Milliseconds 400
    $text = Get-Content -Raw $out
    if ($text -notmatch "listening on 127.0.0.1:(\d+)") { Stop-Process -ErrorAction SilentlyContinue -Id $p.Id -Force; throw "$Stem PE did not listen" }
    $port = [int]$Matches[1]
    try {
        Assert-Case (Read-Http $port "GET" $Path $null) $WantStatus $WantBody $Name
    } finally {
        Stop-Process -ErrorAction SilentlyContinue -Id $p.Id -Force
    }
}
$guestDir = Join-Path $Root "tests/rebuild/guests"
Assert-GuestGet (Join-Path $guestDir "rpc-portal-go.vire") "rebuild-rpc-portal-pe" "/api/capabilities" 200 '{"node":false}' "rpc_capabilities"
Assert-GuestGet (Join-Path $guestDir "rpc-portal-go.vire") "rebuild-rpc-portal-rpc-pe" "/api/rpc" 503 '{"enabled":false,"status":503}' "rpc_rpc_off"
Assert-GuestGet (Join-Path $guestDir "edge-go.vire") "rebuild-edge-pe" "/healthz" 200 "ok" "edge_healthz"
Assert-GuestGet (Join-Path $guestDir "dev-portal-go.vire") "rebuild-dev-portal-pe" "/" 503 '{"reason":"dist_missing","status":503}' "dev_dist_missing"
$dashHealth = '{"ok":true,"service":"fcgbds-dashboard"}' + [char]10
Assert-GuestGet (Join-Path $guestDir "fcgbds-dashboard-go.vire") "rebuild-dash-pe" "/api/health" 200 $dashHealth "dash_health"
Write-Host "CouchStation PE: landing-go unauth fixtures (Linux ELF is tools/rebuild-landing-diff.sh; this is not Linux proof)"
$landingExe = Compile-Guest (Join-Path $Root "tests/rebuild/guests/landing-go.vire") "rebuild-landing-pe"
$lp = Start-Process -FilePath $landingExe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput (Join-Path $Data "rebuild-landing-pe.out") -PassThru
Start-Sleep -Milliseconds 400
$lout = Get-Content -Raw (Join-Path $Data "rebuild-landing-pe.out")
if ($lout -notmatch "listening on 127.0.0.1:(\d+)") { Stop-Process -ErrorAction SilentlyContinue -Id $lp.Id -Force; throw "landing PE did not listen" }
$lport = [int]$Matches[1]
try {
    Assert-Case (Read-Http $lport "GET" "/healthz" $null) 200 'ok' "get_healthz"
    Assert-Case (Read-Http $lport "GET" "/api/capabilities" $null) 200 '{"merch":false,"adsense":false,"adsenseClientId":null,"billing":false}' "get_capabilities"
    Assert-Case (Read-Http $lport "GET" "/api/auth" $null) 401 'Authentication required.' "get_auth"
    Assert-Case (Read-Http $lport "GET" "/api/subscription" $null) 503 '{"enabled":false}' "get_subscription"
    Assert-Case (Read-Http $lport "GET" "/partnership" $null) 307 '{"status":307,"location":"/partners"}' "get_partnership"
    Assert-Case (Read-Http $lport "GET" "/partners" $null) 503 '{"reason":"data_held"}' "get_partners_held"
} finally {
    Stop-Process -ErrorAction SilentlyContinue -Id $lp.Id -Force
}

Write-Host "PASS_AFTER Windows PE rebuild fcgcpa + unauth sidecar + landing-go steps completed on this CouchStation. Linux is not PE proof."
& (Join-Path $PSScriptRoot "native-json-parse-windows.ps1")
