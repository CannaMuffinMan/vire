# Same-source FAIL_BEFORE / PASS_AFTER for conservative-mark / precise-update GC.
# Compiler is the pinned WS compile-native + rt-ws fixture (a6dde53 bytes).
# FAIL_BEFORE: that compiler on 103f189e rt-more (rewrites ambiguous ints).
# PASS_AFTER: that compiler on HEAD rt-more (pin ambiguous, update tagged only).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$FailSha = "103f189e54630f11a127907a84b91faa1b59375c"
$FixDir = Join-Path $Root "tests/native/fixtures/gc-tagged-walk"
Write-Output "fail_before_sha $FailSha"
Write-Output "pass_after_sha $((git rev-parse HEAD).Trim())"
Write-Output "fixture_rt_ws_sha256 2a0d152692b18feb9458f6220900081827b3344b748639f603011997e322f2e3"
Write-Output "fixture_compile_native_sha256 d86df081935e3bce9cbfba3ce1fec79c5aa229336be53ade0569a72d960b07bd"

function Get-NormSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "missing fixture $Path" }
    $text = [IO.File]::ReadAllText($Path) -replace "`r`n", "`n" -replace "`r", "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
        return -join ($bytes | ForEach-Object { $_.ToString("x2") })
    } finally { $sha.Dispose() }
}

function Assert-Fixture {
    $wsPath = Join-Path $FixDir "rt-ws.vire"
    $cnPath = Join-Path $FixDir "compile-native.vire"
    $ws = Get-NormSha256 $wsPath
    $cn = Get-NormSha256 $cnPath
    Write-Output "fixture_rt_ws_got $ws"
    Write-Output "fixture_compile_native_got $cn"
    if ($ws -ne "2a0d152692b18feb9458f6220900081827b3344b748639f603011997e322f2e3") { throw "fixture rt-ws.vire sha $ws" }
    if ($cn -ne "d86df081935e3bce9cbfba3ce1fec79c5aa229336be53ade0569a72d960b07bd") { throw "fixture compile-native.vire sha $cn" }
}

function Patch-HandoffWs([string]$Tree) {
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
    }
    if ($hp -notmatch "gen_hex_first_body_diff") {
        $hp = $hp.Replace(
            'if ($h1 -ne $h2) { throw "gen1/gen2 SHA-256 differ" }',
            @'
if ($h1 -ne $h2) {
    $s1 = [System.IO.File]::ReadAllText($gen1Hex).Trim()
    $s2 = [System.IO.File]::ReadAllText($gen2Hex).Trim()
    $n = [Math]::Min($s1.Length, $s2.Length)
    $k = 1024
    while ($k -lt $n -and $s1[$k] -eq $s2[$k]) { $k++ }
    Write-Output ("gen_hex_first_body_diff " + $k)
    if ($k -lt $n) {
        $even = $k - ($k % 2)
        $a = [Math]::Max(0, $even - 16)
        $b = [Math]::Min($n, $even + 32)
        Write-Output ("gen1_at_body " + $s1.Substring($a, $b - $a))
        Write-Output ("gen2_at_body " + $s2.Substring($a, $b - $a))
    }
    throw "gen1/gen2 SHA-256 differ"
}
'@)
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($handoff, $hp, $utf8)
}

function Install-SameCompiler([string]$Tree, [bool]$FixedGc) {
    $cn = [IO.File]::ReadAllBytes((Join-Path $FixDir "compile-native.vire"))
    $ws = [IO.File]::ReadAllBytes((Join-Path $FixDir "rt-ws.vire"))
    foreach ($rel in @("compile-native.vire", "data/compile-native.vire")) {
        $path = Join-Path $Tree $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        [IO.File]::WriteAllBytes($path, $cn)
    }
    foreach ($rel in @("src/rt-ws.vire", "data/src/rt-ws.vire")) {
        $path = Join-Path $Tree $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        [IO.File]::WriteAllBytes($path, $ws)
    }
    if ($FixedGc) {
        foreach ($rel in @("src/rt-more.vire", "data/src/rt-more.vire")) {
            [IO.File]::Copy((Join-Path $Root $rel), (Join-Path $Tree $rel), $true)
        }
    }
    Patch-HandoffWs $Tree
}

function Get-HandoffSha([string]$Text, [string]$Kind) {
    $m = [regex]::Match($Text, [regex]::Escape($Kind) + " ([0-9a-f]{64})")
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Invoke-FixtureSelfhost([string]$Dir) {
    Push-Location -LiteralPath $Dir
    try {
        if (-not (Test-Path "bin/Release/net10.0/vire.dll")) {
            dotnet build vire.csproj -c Release | Out-Host
        }
        $out = & pwsh -File tools/native-selfhost-handoff.ps1 2>&1 | Out-String
        return @{ Text = $out; Code = $LASTEXITCODE }
    } finally {
        Pop-Location
    }
}

Assert-Fixture
$more = Get-Content -Raw (Join-Path $Root "src/rt-more.vire")
if ($more -notmatch 'rt_gc_mark_pin') { throw "HEAD rt-more missing pin mark" }
if ($more -notmatch 'rt_gc_fwd_one') { throw "HEAD rt-more missing pin-aware compact" }
if ($more -notmatch 'emitKindHdr') { throw "HEAD rt-more missing header kind" }
if ($more -notmatch 'try_zero_loop') { throw "HEAD rt-more missing payload zero" }

git cat-file -t $FailSha 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { git fetch origin $FailSha 2>&1 | Out-Host }

$FailDir = Join-Path $Root "data/fail-before-tagged-gc"
$PassDir = Join-Path $Root "data/pass-after-tagged-gc"
foreach ($d in @($FailDir, $PassDir)) {
    if (Test-Path $d) { git worktree remove --force $d 2>$null; Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue }
}
git worktree add --detach $FailDir $FailSha
git worktree add --detach $PassDir $FailSha
Install-SameCompiler $FailDir $false
Install-SameCompiler $PassDir $true

$before = Invoke-FixtureSelfhost $FailDir
Write-Output $before.Text
Write-Output "FAIL_BEFORE tagged-gc exit $($before.Code)"
$g1b = Get-HandoffSha $before.Text "gen1_sha256"
$g2b = Get-HandoffSha $before.Text "gen2_sha256"
$crashed = ($before.Text -match "crash rip=") -or ($before.Code -eq -1073741819)
$diverged = ($g1b -and $g2b -and $g1b -ne $g2b)
$bodyHint = $before.Text -match "48b9" -or $before.Text -match "00000002" -or $before.Text -match "d4d328"
if (-not $crashed -and -not $diverged) {
    throw "FAIL_BEFORE at $FailSha same WS compiler + untagged GC unexpectedly gen1=gen2 ($g1b)"
}
Write-Output ("FAIL_BEFORE at " + $FailSha + ": same fixture compiler, 103f189e rt-more; crash=" + $crashed + " diverge=" + $diverged + " gen1=" + $g1b + " gen2=" + $g2b)
if ($before.Text -match "gen2_at_body") { Write-Output "FAIL_BEFORE body-diff captured" }
git worktree remove --force $FailDir

$after = Invoke-FixtureSelfhost $PassDir
Write-Output $after.Text
if ($after.Code -ne 0) { throw "PASS_AFTER same fixture compiler + tagged GC exit $($after.Code)" }
$g1 = Get-HandoffSha $after.Text "gen1_sha256"
$g2 = Get-HandoffSha $after.Text "gen2_sha256"
if (-not $g1 -or $g1 -ne $g2) { throw "PASS_AFTER gen1!=gen2 gen1=$g1 gen2=$g2" }
Write-Output "PASS_AFTER same fixture compiler tagged GC gen1=gen2 $g1"
Write-Output "PASS_AFTER tagged-gc gen2 ok"
git worktree remove --force $PassDir
