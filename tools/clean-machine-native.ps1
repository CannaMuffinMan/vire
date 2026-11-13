# Prove gen1.exe compiles a guest with no dotnet on PATH.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null

$gen1 = Join-Path $Root "g1.exe"
if (-not (Test-Path $gen1)) { $gen1 = Join-Path $Data "gen1.exe" }
if (-not (Test-Path $gen1)) { throw "missing gen1.exe (build it with tools/native-selfhost-handoff.ps1 first)" }

$guest = Join-Path $Data "clean-guest.vire"
@(
    "can clock",
    "define main",
    "  let n: number be 1",
    "  say n",
    "end",
    ""
) | Set-Content -Path $guest -Encoding ascii
$hex = Join-Path $Data "clean-guest.hex"
if (Test-Path $hex) { Remove-Item -Force $hex }

$pathParts = @()
foreach ($part in $env:PATH.Split(';')) {
    if ($part -match '(?i)dotnet') { continue }
    $pathParts += $part
}
$env:PATH = [string]::Join(';', $pathParts)
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if ($dotnet) { throw "dotnet still on PATH at $($dotnet.Source)" }
Write-Output "clean_machine_no_dotnet ok"

$p = Start-Process -FilePath $gen1 -ArgumentList @("data/clean-guest.vire", "data/clean-guest.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Data "clean-guest.out.txt") -RedirectStandardError (Join-Path $Data "clean-guest.err.txt")
$out = if (Test-Path (Join-Path $Data "clean-guest.out.txt")) { Get-Content -Raw (Join-Path $Data "clean-guest.out.txt") } else { "" }
Write-Output $out.TrimEnd()
if ($p.ExitCode -ne 0) { throw "gen1 clean guest exit $($p.ExitCode)" }
if ($out -notmatch "capabilities: clock") { throw "missing capabilities: clock" }
if ($out -notmatch "compiled") { throw "missing compiled" }
if (-not (Test-Path $hex)) { throw "missing clean-guest.hex" }
Write-Output "clean_machine_gen1_ok"
