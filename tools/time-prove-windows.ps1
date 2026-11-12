# Host interpreter vs gen1 native PE wall clock and JWT exp.
# Does not raise 32MB arena, 100000 list cap, or 5M step cap.
# Clock is not monotonic; host vs PE may differ by skew (allow +-300s).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
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

function Get-UnixLine($text) {
    $blob = ($text | Out-String)
    foreach ($line in ($blob -split "`n")) {
        $t = $line.Trim()
        if ($t -match '^unix (\d+)$') { return [int64]$Matches[1] }
    }
    throw "missing unix line in:`n$blob"
}

function Get-DetLines($text) {
    $blob = ($text | Out-String)
    $keep = @()
    foreach ($line in ($blob -split "`n")) {
        $t = $line.Trim()
        if ($t -match '^unix ') { continue }
        if ($t.Length -gt 0) { $keep += $t }
    }
    return ($keep -join "`n")
}

$BaseSha = "5b10ea5fa5eea46859f17a52b36037d9d088c01d"
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $((git rev-parse HEAD).Trim())"

$baseVire = git -C $Root show "${BaseSha}:Vire.cs"
if ($baseVire -match 'if \(name == "unix"\)') { throw "base Vire.cs already has unix" }
$basePe = git -C $Root show "${BaseSha}:src/pe.vire"
if ($basePe -match "GetSystemTimeAsFileTime") { throw "base pe.vire already imports GetSystemTimeAsFileTime" }
Write-Output "FAIL_BEFORE at 5b10ea5f: builtin missing / expired JWT accepted"

$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$crypto = Get-Content -Raw (Join-Path $Root "src/rt-crypto.vire")
# Live hole: jwt_hs256_verify with clock none still accepts exp=1.
$beforeGuest = @"
$crypto

define main
  let secret be ascii_bytes with "time-prove-secret"
  let sec be secret at 1
  let dead be jwt_hs256_sign with "{\"exp\":1}", sec
  let got be jwt_hs256_verify with (dead at 1), sec, none
  if (got at 0) == "ok"
    say "FAIL_BEFORE expired JWT accepted at 5b10ea5f"
  end
  if (got at 0) != "ok"
    say "FAIL_BEFORE expected accept"
    halt with 1
  end
end
"@
Set-Content -Path (Join-Path $Data "time-fail-before.vire") -Value $beforeGuest -NoNewline
$beforeOut = & dotnet exec $VireDll data/time-fail-before.vire
$beforeCode = $LASTEXITCODE
Write-Output $beforeOut
Write-Output "time_fail_before_exit $beforeCode"
if ($beforeCode -ne 0) { throw "fail-before guest exit $beforeCode" }
if ("$beforeOut" -notmatch "FAIL_BEFORE expired JWT accepted at 5b10ea5f") { throw "missing FAIL_BEFORE line" }

Write-Output "time_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostOut = & dotnet exec $VireDll time-prove.vire
$code = $LASTEXITCODE
$sw.Stop()
Write-Output $hostOut
Write-Output "time_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "time_host_exit $code"
if ($code -ne 0) { throw "host time-prove exit $code" }
if ("$hostOut" -notmatch "TIME PROVE pass") { throw "host time-prove missing pass" }
if ("$hostOut" -notmatch "EXPIRED JWT REJECT") { throw "host missing expired reject" }
if ("$hostOut" -notmatch "VALID EXP JWT ACCEPT") { throw "host missing valid-exp accept" }
$hostUnix = Get-UnixLine "$hostOut"
if ($hostUnix -le 1767225600) { throw "host unix $hostUnix not after 2026-01-01" }
Write-Output "PASS_AFTER host time-prove"

$lib = Get-Content -Raw (Join-Path $Root "src/rt-crypto.vire")
$prove = Get-Content -Raw (Join-Path $Root "time-prove.vire")
$prove = $prove -replace '(?m)^use "src/rt-crypto.vire"\s*', ''
Set-Content -Path (Join-Path $Data "time-prove.vire") -Value ($lib + "`n" + $prove) -NoNewline
$hexRel = "data/time-prove.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$compileOut = & dotnet exec $VireDll --compiler compile-native.vire data/time-prove.vire $hexRel
$compileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $compileOut
Write-Output "time_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "time_pe_compile_exit $compileCode"
if ($compileCode -ne 0) { throw "compile-native time-prove exit $compileCode" }
if ("$compileOut" -notmatch "compiled") { throw "compile-native missing compiled" }

$exe = Join-Path $Data "time-prove.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$peBytes = [System.IO.File]::ReadAllBytes($exe)
$ascii = [System.Text.Encoding]::ASCII.GetString($peBytes)
if ($ascii.ToLowerInvariant().Contains("ws2_32.dll")) { throw "time PE imported Winsock" }
if (-not $ascii.Contains("GetSystemTimeAsFileTime")) { throw "time PE missing GetSystemTimeAsFileTime" }
Write-Output "time pe imports GetSystemTimeAsFileTime, no Winsock"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peOut = & $exe
$peCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peOut
Write-Output "time_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "time_pe_exit $peCode"
if ($peCode -ne 0) { throw "time PE exit $peCode" }
$peUnix = Get-UnixLine "$peOut"
if ($peUnix -le 1767225600) { throw "PE unix $peUnix not after 2026-01-01" }
$skew = [Math]::Abs($hostUnix - $peUnix)
if ($skew -gt 300) { throw "host unix $hostUnix and PE unix $peUnix differ by ${skew}s (limit 300)" }
Write-Output "time host pe unix skew_s $skew"
$hostDet = Get-DetLines "$hostOut"
$peDet = Get-DetLines "$peOut"
if ($hostDet -ne $peDet) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE stdout differ on deterministic parts"
}
Write-Output "time host pe match"
Write-Output "PASS_AFTER time host and gen1 PE agree"
Write-Output "time windows prove ok"
