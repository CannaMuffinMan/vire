# FAIL_BEFORE: c0e82e0 extra emitFix `if begins with name, "rt_ws"` without
# payload-zero alloc. That gen2 crashed. Grafting the WS emit graph onto
# 103f189e plus the same if still selfhosted (job 132251071056), so that is
# not a FAIL_BEFORE.
# PASS_AFTER: payload-zero alloc + extra if; compile-native does not `use`
# rt-ws.vire (selfhost SHA). gen1 = gen2.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$FailSha = "c0e82e009be51f763d410d58238fd67dedd3e8ff"
Write-Output "fail_before_sha $FailSha"
Write-Output "pass_after_sha $((git rev-parse HEAD).Trim())"

function Get-HandoffSha([string]$Text, [string]$Kind) {
    $m = [regex]::Match($Text, [regex]::Escape($Kind) + " ([0-9a-f]{64})")
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

git cat-file -t $FailSha 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { git fetch origin $FailSha 2>&1 | Out-Host }

$FailDir = Join-Path $Root "data/fail-before-emitfix-if"
if (Test-Path $FailDir) { git worktree remove --force $FailDir 2>$null; Remove-Item -Recurse -Force $FailDir -ErrorAction SilentlyContinue }
git worktree add --detach $FailDir $FailSha
Push-Location -LiteralPath $FailDir
try {
    if (-not (Test-Path "bin/Release/net10.0/vire.dll")) {
        dotnet build vire.csproj -c Release | Out-Host
    }
    $before = & pwsh -File tools/native-selfhost-handoff.ps1 2>&1 | Out-String
    $beforeCode = $LASTEXITCODE
} finally {
    Pop-Location
}
Write-Output $before
Write-Output "FAIL_BEFORE emitfix-if exit $beforeCode"
if ($beforeCode -eq 0) { throw "FAIL_BEFORE at $FailSha extra emitFix if unexpectedly selfhosted" }
if ($before -notmatch "crash rip=" -and $before -notmatch "crash_access_violation" -and $before -notmatch "exit -1073741819") {
    throw "FAIL_BEFORE at $FailSha expected gen2 crash, got $before"
}
Write-Output ("FAIL_BEFORE at " + $FailSha + ": extra emitFix if crashed gen2 (unzeroed alloc tail / GC)")
git worktree remove --force $FailDir

$cn = Get-Content -Raw (Join-Path $Root "compile-native.vire")
if ($cn -notmatch 'begins with name, "rt_ws"') { throw "PASS_AFTER compile-native missing extra emitFix if" }
if ($cn -match 'use "src/rt-ws.vire"') { throw "PASS_AFTER compile-native must not use rt-ws.vire (selfhost SHA)" }
$after = & pwsh -File tools/native-selfhost-handoff.ps1 2>&1 | Out-String
Write-Output $after
if ($LASTEXITCODE -ne 0) { throw "PASS_AFTER native-selfhost-windows exit $LASTEXITCODE" }
$g1 = Get-HandoffSha $after "gen1_sha256"
$g2 = Get-HandoffSha $after "gen2_sha256"
if (-not $g1 -or $g1 -ne $g2) { throw "PASS_AFTER gen1!=gen2 gen1=$g1 gen2=$g2" }
Write-Output "PASS_AFTER extra emitFix if gen1=gen2 $g1"
Write-Output "PASS_AFTER emitfix-if gen2 ok"
