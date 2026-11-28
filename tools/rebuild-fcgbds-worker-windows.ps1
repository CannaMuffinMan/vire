# Windows PE proof steps for CouchStation. This agent did not run these.
# Do not treat a missing gen1 PE on Linux as a Windows result.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_HEADLESS = "1"
$env:VIRE_BUDGET = "5000000"
$Data = Join-Path $Root "data"
$VireDll = Join-Path $Root "bin\Release\net10.0\vire.dll"
$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing data/gen1.exe; run native-selfhost-handoff.ps1 on Windows first" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

Copy-Item (Join-Path $Root "guest-fcgbds.vire") (Join-Path $Data "guest-fcgbds.vire") -Force
Copy-Item (Join-Path $Root "guest-worker.vire") (Join-Path $Data "guest-worker.vire") -Force

$hex = Join-Path $Data "guest-fcgbds.hex"
$exe = Join-Path $Data "guest-fcgbds.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
$p = Start-Process -FilePath $gen1 -ArgumentList @("data/guest-fcgbds.vire", "data/guest-fcgbds.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "gen1 fcgbds compile exit $($p.ExitCode)" }
Convert-HexToExe $hex $exe

$whex = Join-Path $Data "guest-worker.hex"
$wexe = Join-Path $Data "guest-worker.exe"
if (Test-Path $whex) { Remove-Item -Force $whex }
$p = Start-Process -FilePath $gen1 -ArgumentList @("data/guest-worker.vire", "data/guest-worker.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "gen1 worker compile exit $($p.ExitCode)" }
Convert-HexToExe $whex $wexe

Write-Host "PE files written. Replay tests/rebuild/contracts/fcgbds-go.json against guest-fcgbds.exe listen (loopback)."
Write-Host "Heartbeat POST /api/bot-defense/reviewers/heartbeat JSON body {} and empty sessionId 400; {\"sessionId\":\"abc-1\"} 200 live=1. Do not use query sessionId=."
Write-Host "Worker: guest-worker.exe PAYMENTS_ENABLED=1 exit 1; no args disabled exit 0; FCG_WORKER_ENABLED=1 no jobs disabled exit 0; FCG_WORKER_ENABLED=1 FCG_JOB_AGGREGATION=1 and FCG_JOB_FCGBDS_CLEANUP=1 skeleton refusal exit 0."
Write-Host "Reserved: guest-fcgbds.exe 7099 and 8778 must print refusing reserved port and exit 1."
Write-Host "PASS_AFTER PE files written (MZ compile). Replay remaining worker cases on CouchStation. This agent did not run PE."
