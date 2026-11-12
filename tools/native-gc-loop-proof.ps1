# Fail-before / pass-after for native GC and loop budget on a real Windows PE.
# Does not raise the 32MB arena, 2e6 spin cap, or 5e6 step cap.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
git fetch origin native-compiler
$BaseSha = (git rev-parse origin/native-compiler).Trim()
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $out = & dotnet exec $VireDll @Args
    $code = $LASTEXITCODE
    if ($null -ne $out) { $out | Write-Host }
    if ($null -eq $code) { return 0 }
    return [int]$code
}

function Convert-HexToExe {
    param([string]$HexPath, [string]$ExePath)
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Compile-Run {
    param([string]$Name, [string]$Src)
    $work = Join-Path $Root "data/native-gc-loop"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $srcRel = "data/native-gc-loop/$Name.vire"
    $hexRel = "data/native-gc-loop/$Name.hex"
    Copy-Item $Src (Join-Path $Root $srcRel) -Force
    $code = Invoke-Vire compile-native.vire $srcRel $hexRel
    if ($code -ne 0) { throw "compile $Name failed exit=$code" }
    $exe = Join-Path $work "$Name.exe"
    Convert-HexToExe (Join-Path $Root $hexRel) $exe
    $got = ""
    $exit = 0
    try {
        $got = (& $exe 2>&1 | Out-String)
        $exit = $LASTEXITCODE
    } catch {
        $got = $_.ToString()
        $exit = $LASTEXITCODE
    }
    return @{ Exit = [int]$exit; Out = "$got".Trim(); Exe = $exe }
}

function Restore-RuntimeFrom {
    param([string]$Sha)
    git checkout $Sha -- src/rt.vire src/rt-more.vire data/src/rt.vire data/src/rt-more.vire compile-native.vire data/compile-native.vire
    if ($LASTEXITCODE -ne 0) { throw "checkout runtime from $Sha failed" }
}

$Work = Join-Path $Root "data/native-gc-loop"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null

Write-Output "phase fail-before $BaseSha"
Restore-RuntimeFrom $BaseSha
$beforeGc = Compile-Run "gc-churn-before" (Join-Path $Root "tests/native/gc-churn.vire")
Write-Output "before_gc exit=$($beforeGc.Exit) out=$($beforeGc.Out)"
if ($beforeGc.Exit -eq 1 -and $beforeGc.Out.Contains("out of memory")) {
    Write-Output "FAIL_BEFORE gc-churn OOM at $BaseSha"
} else {
    throw "fail-before gc-churn expected OOM, got exit=$($beforeGc.Exit) out=$($beforeGc.Out)"
}
$beforeSpin = Compile-Run "while-spin-before" (Join-Path $Root "tests/native/while-spin.vire")
Write-Output "before_spin exit=$($beforeSpin.Exit) out=$($beforeSpin.Out)"
if ($beforeSpin.Exit -eq 1 -and $beforeSpin.Out.Contains("while ran too long")) {
    Write-Output "FAIL_BEFORE while-spin at $BaseSha"
} else {
    throw "fail-before while-spin expected while ran too long"
}

Write-Output "phase pass-after $AfterSha"
Restore-RuntimeFrom $AfterSha
$afterGc = Compile-Run "gc-churn-after" (Join-Path $Root "tests/native/gc-churn.vire")
Write-Output "after_gc exit=$($afterGc.Exit) out=$($afterGc.Out)"
if ($afterGc.Exit -ne 0 -or $afterGc.Out -ne "7") {
    throw "pass-after gc-churn expected 7 exit 0, got exit=$($afterGc.Exit) out=$($afterGc.Out)"
}
Write-Output "PASS_AFTER gc-churn at $AfterSha"
$afterTurns = Compile-Run "while-turns-after" (Join-Path $Root "tests/native/while-turns.vire")
Write-Output "after_turns exit=$($afterTurns.Exit) out=$($afterTurns.Out)"
if ($afterTurns.Exit -ne 0 -or $afterTurns.Out -ne "ok") {
    throw "pass-after while-turns expected ok; 2.5e6 trips with ticks resets. Got exit=$($afterTurns.Exit) out=$($afterTurns.Out)"
}
Write-Output "PASS_AFTER while-turns 2500000 trips at $AfterSha"
$afterSpin = Compile-Run "while-spin-after" (Join-Path $Root "tests/native/while-spin.vire")
Write-Output "after_spin exit=$($afterSpin.Exit) out=$($afterSpin.Out)"
if ($afterSpin.Exit -eq 1 -and $afterSpin.Out.Contains("while ran too long")) {
    Write-Output "PASS_AFTER while-spin still bounded at $AfterSha"
} else {
    throw "pass-after while-spin must still die at 2e6 consecutive trips"
}

Write-Output "native gc/loop proof ok"
Write-Output "note: a truly infinite accept loop is not shown in CI; ticks/rt_note_wait reset the 2e6 spin counter per turn, then this job shuts down after 2.5e6 counted trips."
exit 0
