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
    $p = Start-Process -FilePath $gen1 -ArgumentList @("data/$Stem.vire", "data/$Stem.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "gen1 $Stem compile exit $($p.ExitCode)" }
    Convert-HexToExe $hex $exe
    return $exe
}

function Read-Http([int]$Port, [string]$Method, [string]$Path, [string]$Send) {
    $payload = if ($null -eq $Send) { [byte[]]@() } else { [System.Text.Encoding]::UTF8.GetBytes($Send) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$Method $Path HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n")
    if ($Method -eq "POST") {
        [void]$sb.Append("Content-Type: application/json`r`nContent-Length: $($payload.Length)`r`n")
    }
    [void]$sb.Append("`r`n")
    $head = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $stream.Write($head, 0, $head.Length)
    if ($payload.Length -gt 0) { $stream.Write($payload, 0, $payload.Length) }
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 4096
    while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    $tcp.Close()
    $raw = $ms.ToArray()
    $text = [System.Text.Encoding]::UTF8.GetString($raw)
    $split = $text.IndexOf("`r`n`r`n")
    $start = $text.Substring(0, $split)
    $body = $text.Substring($split + 4)
    $status = [int]($start.Split(" ")[1])
    return @{ Status = $status; Body = $body }
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
if ($hout -notmatch "listening on 127.0.0.1:(\d+)") { Stop-Process -Id $hp.Id -Force; throw "health PE did not listen" }
$hport = [int]$Matches[1]
try {
    Assert-Case (Read-Http $hport "GET" "/payments" $null) 403 '{"ok":false,"status":403,"error":"payments are off"}' "get_payments"
    Assert-Case (Read-Http $hport "GET" "/mine" $null) 403 '{"ok":false,"status":403,"error":"mining stays inside the app"}' "get_mine"
} finally {
    Stop-Process -Id $hp.Id -Force
}

$cp = Start-Process -FilePath $chainExe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput (Join-Path $Data "rebuild-chain-pe.out") -PassThru
Start-Sleep -Milliseconds 400
$cout = Get-Content -Raw (Join-Path $Data "rebuild-chain-pe.out")
if ($cout -notmatch "listening on 127.0.0.1:(\d+)") { Stop-Process -Id $cp.Id -Force; throw "chain PE did not listen" }
$cport = [int]$Matches[1]
try {
    Assert-Case (Read-Http $cport "GET" "/chain" $null) 200 '[{"index":0,"previous":"0","proof":"a9df21e6e7672bdb9cea28047aa39ba0fa96d54ae0791a9bab30078f5a2d4fad","text":""}]' "get_chain_genesis"
    Assert-Case (Read-Http $cport "POST" "/block" "not-json") 400 '{"ok":false,"status":400,"error":"bad block"}' "post_block_not_json"
    Copy-Item (Join-Path $Root "data/rebuild/chain/head.json") (Join-Path $Data "chain/head.json") -Force
    Copy-Item (Join-Path $Root "data/rebuild/chain/000001.json") (Join-Path $Data "chain/000001.json") -Force
    Assert-Case (Read-Http $cport "POST" "/block" '{"text":"fixture-one"}') 200 '{"ok":true,"accepted":true,"index":1,"proof":"52d7f3a9d3dfa0458a20ff820cab94c1df2acea128dacd450a6e45456c27f561"}' "post_block_accept_fixture_one"
} finally {
    Stop-Process -Id $cp.Id -Force
}

Write-Host "CouchStation PE: unauth sidecar guests (rpc-portal-go, edge-go, dev-portal-go, fcgbds-dashboard-go)"
function Assert-GuestGet([string]$Src, [string]$Stem, [string]$Path, [int]$WantStatus, [string]$WantBody, [string]$Name) {
    $exe = Compile-Guest $Src $Stem
    $out = Join-Path $Data "$Stem.out"
    $p = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput $out -PassThru
    Start-Sleep -Milliseconds 400
    $text = Get-Content -Raw $out
    if ($text -notmatch "listening on 127.0.0.1:(\d+)") { Stop-Process -Id $p.Id -Force; throw "$Stem PE did not listen" }
    $port = [int]$Matches[1]
    try {
        Assert-Case (Read-Http $port "GET" $Path $null) $WantStatus $WantBody $Name
    } finally {
        Stop-Process -Id $p.Id -Force
    }
}
$guestDir = Join-Path $Root "tests/rebuild/guests"
Assert-GuestGet (Join-Path $guestDir "rpc-portal-go.vire") "rebuild-rpc-portal-pe" "/api/capabilities" 200 '{"node":false}' "rpc_capabilities"
Assert-GuestGet (Join-Path $guestDir "rpc-portal-go.vire") "rebuild-rpc-portal-rpc-pe" "/api/rpc" 503 '{"enabled":false,"status":503}' "rpc_rpc_off"
Assert-GuestGet (Join-Path $guestDir "edge-go.vire") "rebuild-edge-pe" "/healthz" 200 "ok" "edge_healthz"
Assert-GuestGet (Join-Path $guestDir "dev-portal-go.vire") "rebuild-dev-portal-pe" "/" 503 '{"reason":"dist_missing","status":503}' "dev_dist_missing"
$dashHealth = '{"ok":true,"service":"fcgbds-dashboard"}' + [char]10
Assert-GuestGet (Join-Path $guestDir "fcgbds-dashboard-go.vire") "rebuild-dash-pe" "/api/health" 200 $dashHealth "dash_health"
Write-Host "Windows PE rebuild fcgcpa + unauth sidecar steps completed on this CouchStation. Linux is not PE proof."
