# Host + gen1 PE proof for types and capabilities on Windows.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$HeadSha = (git rev-parse HEAD).Trim()
Write-Output "HEAD_SHA $HeadSha"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }

$probe = @"
can clock
define main
  let n: number be 1
  say n
end
"@
Set-Content -Path (Join-Path $Data "lang-probe.vire") -Value $probe -Encoding ascii
$hex = Join-Path $Data "lang-probe.hex"
if (Test-Path $hex) { Remove-Item -Force $hex }

$p = Start-Process -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/lang-probe.vire") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Data "lang-probe.host.out.txt") -RedirectStandardError (Join-Path $Data "lang-probe.host.err.txt")
$hostOut = Get-Content -Raw (Join-Path $Data "lang-probe.host.out.txt")
if ($p.ExitCode -ne 0) { throw "host probe exit $($p.ExitCode)" }
if ($hostOut.Trim() -ne "1") { throw "host probe stdout $hostOut" }
Write-Output "PASS_AFTER host typed clock probe at $HeadSha"

Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$p = Start-Process -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "--compiler", "compile-native.vire", "data/lang-probe.vire", "data/lang-probe.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Data "lang-probe.native.out.txt") -RedirectStandardError (Join-Path $Data "lang-probe.native.err.txt")
$natOut = Get-Content -Raw (Join-Path $Data "lang-probe.native.out.txt")
Write-Output $natOut.TrimEnd()
if ($p.ExitCode -ne 0) { throw "host compile-native probe exit $($p.ExitCode)" }
if ($natOut -notmatch "capabilities: clock") { throw "missing capabilities: clock" }
if ($natOut -notmatch "compiled") { throw "missing compiled" }
Write-Output "PASS_AFTER compile-native typed clock probe at $HeadSha"

$gen1 = Join-Path $Root "g1.exe"
if (-not (Test-Path $gen1)) { $gen1 = Join-Path $Data "gen1.exe" }
if (Test-Path $gen1) {
    $ghex = Join-Path $Data "lang-probe-gen1.hex"
    if (Test-Path $ghex) { Remove-Item -Force $ghex }
    $p = Start-Process -FilePath $gen1 -ArgumentList @("data/lang-probe.vire", "data/lang-probe-gen1.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Data "lang-probe.gen1.out.txt") -RedirectStandardError (Join-Path $Data "lang-probe.gen1.err.txt")
    $gOut = Get-Content -Raw (Join-Path $Data "lang-probe.gen1.out.txt")
    Write-Output $gOut.TrimEnd()
    if ($p.ExitCode -ne 0) { throw "gen1 probe exit $($p.ExitCode)" }
    if ($gOut -notmatch "capabilities: clock") { throw "gen1 missing capabilities: clock" }
    if ($gOut -notmatch "compiled") { throw "gen1 missing compiled" }
    Convert-HexToExe $ghex (Join-Path $Data "lang-probe-gen1.exe")
    $exe = Join-Path $Data "lang-probe-gen1.exe"
    try { Unblock-File -Path $exe } catch { }
    $p = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Data "lang-probe-gen1.run.out.txt") -RedirectStandardError (Join-Path $Data "lang-probe-gen1.run.err.txt")
    $run = Get-Content -Raw (Join-Path $Data "lang-probe-gen1.run.out.txt")
    if ($p.ExitCode -ne 0) { throw "gen1 PE run exit $($p.ExitCode)" }
    if ($run.Trim() -ne "1") { throw "gen1 PE stdout $run" }
    Write-Output "PASS_AFTER gen1 PE typed clock probe at $HeadSha"
} else {
    Write-Output "gen1.exe missing; skip PE run"
}
