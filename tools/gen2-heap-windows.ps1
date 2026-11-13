# FAIL_BEFORE: list cap fail-open (5b10ea5f) + gen2 SHA drift (04724f2c).
# PASS_AFTER: fail-closed 100000 + emitFix so gen2 finishes; 3× same SHA.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$FailSha = "04724f2c9a9d26c352ec31b62e0402d3503d199c"
$CapSha = "5b10ea5fa5eea46859f17a52b36037d9d088c01d"
Write-Output "fail_before_sha $FailSha"
Write-Output "fail_before_cap_sha $CapSha"

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Invoke-ListCapPe([string]$Tree, [string]$Src) {
    Push-Location -LiteralPath $Tree
    try {
        if (-not (Test-Path "bin/Release/net10.0/vire.dll")) {
            dotnet build vire.csproj -c Release | Out-Host
        }
        New-Item -ItemType Directory -Force -Path "data" | Out-Null
        Copy-Item $Src "data/list-cap-corrupt.vire" -Force
        $saved = $env:VIRE_BUDGET
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
        $env:VIRE_HEADLESS = "1"
        & dotnet exec "bin/Release/net10.0/vire.dll" --compiler compile-native.vire data/list-cap-corrupt.vire data/list-cap-corrupt.hex
        if ($saved) { $env:VIRE_BUDGET = $saved }
        Convert-HexToExe (Join-Path $Tree "data/list-cap-corrupt.hex") (Join-Path $Tree "data/list-cap-corrupt.exe")
        $out = & (Join-Path $Tree "data/list-cap-corrupt.exe") 2>&1 | Out-String
        $code = $LASTEXITCODE
        return [pscustomobject]@{ Code = $code; Out = $out }
    } finally {
        Pop-Location
    }
}

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
if ($LASTEXITCODE -ne 0) { git fetch origin $FailSha $CapSha 2>&1 | Out-Host }
git cat-file -t $CapSha 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { git fetch origin $CapSha 2>&1 | Out-Host }

$CapDir = Join-Path $Root "data/fail-before-list-cap"
if (Test-Path $CapDir) { git worktree remove --force $CapDir 2>$null; Remove-Item -Recurse -Force $CapDir -ErrorAction SilentlyContinue }
git worktree add --detach $CapDir $CapSha
$cap = Invoke-ListCapPe $CapDir (Join-Path $Root "tests/native/list-cap-corrupt.vire")
Write-Output $cap.Out
Write-Output "FAIL_BEFORE list-cap exit $($cap.Code)"
if ($cap.Out -match "list is too large") { throw "FAIL_BEFORE at $CapSha unexpectedly fail-closed" }
if ($cap.Out -notmatch "crash " -and $cap.Out -notmatch "an index must be a whole number") {
    throw "FAIL_BEFORE at $CapSha expected intern/rt_at smash, got $($cap.Out)"
}
Write-Output ("FAIL_BEFORE at " + $CapSha + ": 100001 pushes did not raise list is too large (exit " + $cap.Code + "); at `"id`" intern/rt_at path")
git worktree remove --force $CapDir
Write-Output ("FAIL_BEFORE recorded SHA drift at " + $FailSha + ": gen1 09fc0afb vs gen2 abc6c092 (native-net 132147041715, #86 selfhost 132169879533) and 1db10b7a (selfhost 132147042612); not re-probed here because three matching 09fc0afb runs are not a counterexample")

$afterCap = Invoke-ListCapPe $Root (Join-Path $Root "tests/native/list-cap-corrupt.vire")
Write-Output $afterCap.Out
if ($afterCap.Out -notmatch "list is too large") { throw "PASS_AFTER list-cap expected list is too large, got $($afterCap.Out)" }
if ($afterCap.Out -match "crash ") { throw "PASS_AFTER list-cap crashed" }
Write-Output "PASS_AFTER list cap fail-closed"

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
