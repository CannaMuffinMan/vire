# Windows PE proof for fcgbds-go heartbeat JSON sessionId.
# CouchStation only. This Linux lane did not run this script. Do not touch Defender.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
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

New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $Root "tests/rebuild/guests/fcgbds-heartbeat.vire") (Join-Path $Data "fcgbds-heartbeat.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/fcgbds-heartbeat-fail.vire") (Join-Path $Data "fcgbds-heartbeat-fail.vire") -Force

$hex = Join-Path $Data "fcgbds-heartbeat.hex"
$exe = Join-Path $Data "fcgbds-heartbeat.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
$p = Start-Process -FilePath $gen1 -ArgumentList @("data/fcgbds-heartbeat.vire", "data/fcgbds-heartbeat.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "gen1 heartbeat compile exit $($p.ExitCode)" }
Convert-HexToExe $hex $exe
$pe = [System.IO.File]::ReadAllBytes($exe)
if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "heartbeat PE missing MZ" }

Write-Host "PE written data/fcgbds-heartbeat.exe. Replay tests/rebuild/contracts/fcgbds-heartbeat.json on loopback (host vire.dll vs this PE)."
Write-Host "FAIL_BEFORE: compile data/fcgbds-heartbeat-fail.vire the same way; JSON sessionId must mismatch."
Write-Host "This Linux agent did not run this script."
