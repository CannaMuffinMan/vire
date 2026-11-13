# FAIL_BEFORE: tip 103f189e + one extra emitFix `if` → gen2 ACCESS_VIOLATION.
# PASS_AFTER: payload-zero alloc + the same extra if; gen1 SHA = gen2 SHA.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$FailSha = "103f189e54630f11a127907a84b91faa1b59375c"
Write-Output "fail_before_sha $FailSha"
Write-Output "pass_after_sha $((git rev-parse HEAD).Trim())"

function Add-EmitFixIf([string]$Tree) {
    foreach ($rel in @("compile-native.vire", "data/compile-native.vire")) {
        $path = Join-Path $Tree $rel
        $norm = ([IO.File]::ReadAllText($path) -replace "`r`n", "`n")
        if ($norm.Contains('begins with name, "rt_ws"')) { continue }
        $old = "  if begins with name, `"rt_json`"`n    let later be true`n  end`n"
        if (-not $norm.Contains($old)) { throw "emitFix json if missing in $rel" }
        $norm = $norm.Replace($old, $old + "  if begins with name, `"rt_ws`"`n    let later be true`n  end`n")
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($path, $norm, $utf8)
    }
}

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
Add-EmitFixIf $FailDir
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
if ($before -notmatch "crash rip=") { throw "FAIL_BEFORE at $FailSha expected crash rip=, got $before" }
Write-Output ("FAIL_BEFORE at " + $FailSha + ": one extra emitFix if crashed gen2 (unzeroed alloc tail / GC)")
git worktree remove --force $FailDir

$cn = Get-Content -Raw (Join-Path $Root "compile-native.vire")
if ($cn -notmatch 'begins with name, "rt_ws"') { throw "PASS_AFTER compile-native missing extra emitFix if" }
$after = & pwsh -File tools/native-selfhost-handoff.ps1 2>&1 | Out-String
Write-Output $after
if ($LASTEXITCODE -ne 0) { throw "PASS_AFTER native-selfhost-windows exit $LASTEXITCODE" }
$g1 = Get-HandoffSha $after "gen1_sha256"
$g2 = Get-HandoffSha $after "gen2_sha256"
if (-not $g1 -or $g1 -ne $g2) { throw "PASS_AFTER gen1!=gen2 gen1=$g1 gen2=$g2" }
Write-Output "PASS_AFTER extra emitFix if gen1=gen2 $g1"
Write-Output "PASS_AFTER emitfix-if gen2 ok"
