# FAIL_BEFORE: tip 103f189e + one extra emitFix `if` + the WS emit graph
# (same compiler growth that crashed #68 selfhost). Unzeroed alloc tails AV
# in gen2. PASS_AFTER: payload-zero alloc + the same extra if; gen1 = gen2.
# One extra if at 103f189e without that graph still selfhosts (job 132246434278).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$FailSha = "103f189e54630f11a127907a84b91faa1b59375c"
$WsSha = "c0e82e009be51f763d410d58238fd67dedd3e8ff"
Write-Output "fail_before_sha $FailSha"
Write-Output "pass_after_sha $((git rev-parse HEAD).Trim())"

function Get-RtWsBytes {
    $local = Join-Path $Root "src/rt-ws.vire"
    if (Test-Path -LiteralPath $local) { return [IO.File]::ReadAllBytes($local) }
    foreach ($rev in @("origin/cursor/guest-ws-server-cf75", $WsSha)) {
        git cat-file -e "${rev}:src/rt-ws.vire" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { continue }
        $lines = git show "${rev}:src/rt-ws.vire"
        if ($LASTEXITCODE -eq 0 -and $lines) {
            return [Text.Encoding]::UTF8.GetBytes((($lines | ForEach-Object { $_ }) -join "`n") + "`n")
        }
    }
    git fetch origin cursor/guest-ws-server-cf75 2>&1 | Out-Host
    $lines = git show origin/cursor/guest-ws-server-cf75:src/rt-ws.vire
    if ($LASTEXITCODE -ne 0 -or -not $lines) { throw "need src/rt-ws.vire for FAIL_BEFORE compiler growth" }
    return [Text.Encoding]::UTF8.GetBytes((($lines | ForEach-Object { $_ }) -join "`n") + "`n")
}

function Add-EmitFixIf([string]$Tree) {
    $wsBytes = Get-RtWsBytes
    foreach ($rel in @("src/rt-ws.vire", "data/src/rt-ws.vire")) {
        $wsPath = Join-Path $Tree $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $wsPath) | Out-Null
        [IO.File]::WriteAllBytes($wsPath, $wsBytes)
    }
    foreach ($rel in @("compile-native.vire", "data/compile-native.vire")) {
        $path = Join-Path $Tree $rel
        $norm = ([IO.File]::ReadAllText($path) -replace "`r`n", "`n")
        if ($norm -notmatch 'use "src/rt-ws.vire"') {
            $useNet = 'use "src/rt-net.vire"'
            if (-not $norm.Contains($useNet)) { throw "rt-net use missing in $rel" }
            $norm = $norm.Replace($useNet, $useNet + "`nuse `"src/rt-ws.vire`"")
        }
        if (-not $norm.Contains('begins with name, "rt_ws"')) {
            $old = "  if begins with name, `"rt_json`"`n    let later be true`n  end`n"
            if (-not $norm.Contains($old)) { throw "emitFix json if missing in $rel" }
            $norm = $norm.Replace($old, $old + "  if begins with name, `"rt_ws`"`n    let later be true`n  end`n")
        }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($path, $norm, $utf8)
    }
    $handoff = Join-Path $Tree "tools/native-selfhost-handoff.ps1"
    $hp = [IO.File]::ReadAllText($handoff)
    if ($hp -notmatch "rt-ws.vire") {
        $hp = $hp.Replace(
            'Copy-Item (Join-Path $Root "src/rt-net.vire") (Join-Path $Src "rt-net.vire") -Force',
            'Copy-Item (Join-Path $Root "src/rt-net.vire") (Join-Path $Src "rt-net.vire") -Force' + "`r`n" + 'Copy-Item (Join-Path $Root "src/rt-ws.vire") (Join-Path $Src "rt-ws.vire") -Force')
        $hp = $hp.Replace(
            '@("src/rt-net.vire", "data/src/rt-net.vire"),',
            '@("src/rt-net.vire", "data/src/rt-net.vire"),' + "`r`n" + '    @("src/rt-ws.vire", "data/src/rt-ws.vire"),')
        if ($hp -notmatch "rt-ws.vire") { throw "could not patch selfhost handoff to copy rt-ws" }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($handoff, $hp, $utf8)
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
if ($beforeCode -eq 0) { throw "FAIL_BEFORE at $FailSha extra emitFix if + rt-ws graph unexpectedly selfhosted" }
if ($before -notmatch "crash rip=") { throw "FAIL_BEFORE at $FailSha expected crash rip=, got $before" }
Write-Output ("FAIL_BEFORE at " + $FailSha + ": extra emitFix if plus WS emit graph crashed gen2 (unzeroed alloc tail / GC)")
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
