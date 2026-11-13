# FAIL_BEFORE: gen2 SHA drift at tip 04724f2c (#85). PASS_AFTER: this GC fix, 3× same SHA.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$FailSha = "04724f2c9a9d26c352ec31b62e0402d3503d199c"
Write-Output "fail_before_sha $FailSha"

function Get-HandoffSha([string]$Text, [string]$Kind) {
    $m = [regex]::Match($Text, [regex]::Escape($Kind) + " ([0-9a-f]{64})")
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Invoke-HandoffCapture([string]$Tree) {
    Push-Location -LiteralPath $Tree
    try {
        if (-not (Test-Path "bin/Release/net10.0/vire.dll")) {
            dotnet build vire.csproj -c Release | Out-Host
        }
        $out = & pwsh -File tools/native-selfhost-handoff.ps1 2>&1 | Out-String
        $code = $LASTEXITCODE
        Write-Output $out
        return [pscustomobject]@{
            Code = $code
            Out  = $out
            Gen1 = Get-HandoffSha $out "gen1_sha256"
            Gen2 = Get-HandoffSha $out "gen2_sha256"
        }
    } finally {
        Pop-Location
    }
}

git cat-file -t $FailSha 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { git fetch origin $FailSha 2>&1 | Out-Host }

$FailDir = Join-Path $Root "data/fail-before-gen2"
if (Test-Path $FailDir) { git worktree remove --force $FailDir 2>$null; Remove-Item -Recurse -Force $FailDir -ErrorAction SilentlyContinue }
git worktree add --detach $FailDir $FailSha

$saw = $false
$gen2Seen = New-Object "System.Collections.Generic.HashSet[string]"
for ($i = 1; $i -le 8; $i++) {
    $r = Invoke-HandoffCapture $FailDir
    Write-Output "FAIL_BEFORE run $i exit $($r.Code) gen1=$($r.Gen1) gen2=$($r.Gen2)"
    if ($r.Gen1 -and $r.Gen2 -and ($r.Gen1 -ne $r.Gen2)) { $saw = $true; break }
    if ($r.Gen2) { [void]$gen2Seen.Add($r.Gen2) }
    if ($gen2Seen.Count -gt 1) { $saw = $true; break }
    if ($r.Code -ne 0 -and -not $r.Gen2) { $saw = $true; break }
}
if (-not $saw) {
    throw "FAIL_BEFORE at $FailSha expected gen1!=gen2 or varying gen2 (jobs 132147041715 abc6c092, 132169879533 abc6c092, 132147042612 1db10b7a vs gen1 09fc0afb)"
}
Write-Output "FAIL_BEFORE at $FailSha: gen2 SHA not deterministic vs gen1 09fc0afb (native-net 132147041715, native-selfhost 132147042612 / 132169879533)"
git worktree remove --force $FailDir

$passShas = New-Object System.Collections.Generic.List[string]
for ($i = 1; $i -le 3; $i++) {
    $r = Invoke-HandoffCapture $Root
    if ($r.Code -ne 0) { throw "PASS_AFTER native-selfhost-windows run $i exit $($r.Code)" }
    if (-not $r.Gen1 -or $r.Gen1 -ne $r.Gen2) { throw "PASS_AFTER gen1!=gen2 run $i gen1=$($r.Gen1) gen2=$($r.Gen2)" }
    $passShas.Add($r.Gen1)
    Write-Output "PASS_AFTER selfhost run $i sha $($r.Gen1)"
    & pwsh -File tools/native-net-windows.ps1
    if ($LASTEXITCODE -ne 0) { throw "PASS_AFTER native-net-windows run $i exit $LASTEXITCODE" }
    Write-Output "PASS_AFTER net run $i ok"
}
$uniq = $passShas | Select-Object -Unique
if (@($uniq).Count -ne 1) { throw "PASS_AFTER SHA varied across 3 runs: $($passShas -join ',')" }
Write-Output "PASS_AFTER 3x native-selfhost-windows + native-net-windows same sha $($uniq)"
Write-Output "PASS_AFTER gen2 heap ok"
