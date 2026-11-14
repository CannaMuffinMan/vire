# Fail-before / pass-after for native GC and loop budget on a real Windows PE.
# Does not raise the 32MB arena, 2e6 spin cap, or 5e6 step cap.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
git fetch origin native-compiler
# Pin the pre-GC tree. origin/native-compiler is #57 (GC already present).
$BaseSha = "7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $leaf = [IO.Path]::GetFileName($Args[0])
    $savedBudget = $env:VIRE_BUDGET
    if ($leaf -eq "compile-native.vire" -or $leaf -eq "compiler.vire") {
        $Args = @("--compiler") + $Args
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    }
    try {
    $out = & dotnet exec $VireDll @Args
    $code = $LASTEXITCODE
    if ($null -ne $out) { $out | Write-Host }
    if ($null -eq $code) { return 0 }
    return [int]$code
    } finally {
        if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
    }
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
    git cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        git fetch --depth 1 origin $Sha
        git cat-file -e "$Sha^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) { throw "missing commit $Sha" }
    }
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
$afterKind = Compile-Run "gc-kind-stress-after" (Join-Path $Root "tests/native/gc-kind-stress.vire")
Write-Output "after_kind exit=$($afterKind.Exit) out=$($afterKind.Out)"
if ($afterKind.Exit -ne 0 -or $afterKind.Out -ne "gc-kind-stress ok") {
    throw "pass-after gc-kind-stress expected gc-kind-stress ok exit 0, got exit=$($afterKind.Exit) out=$($afterKind.Out)"
}
Write-Output "PASS_AFTER gc-kind-stress at $AfterSha"
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

function Set-TextcatKeep {
    param([string]$Src, [string]$Dst, [int]$Keep)
    $text = [IO.File]::ReadAllText($Src)
    $updated = $text.Replace("while n < 470", "while n < $Keep")
    [IO.File]::WriteAllText($Dst, $updated)
}

function Assert-TextcatClosed {
    param($Result, [int]$Keep, [string]$Phase)
    $out = "$($Result.Out)"
    if ($out.Contains("textcat corrupt") -or $out.Contains("crash ")) {
        throw "$Phase textcat keep=$Keep crash/corrupt exit=$($Result.Exit) out=$out"
    }
    if ($Result.Exit -eq 0 -and $out.Contains("textcat ok")) { return }
    if ($Result.Exit -eq 1 -and $out.Contains("out of memory")) { return }
    throw "$Phase textcat keep=$Keep expected ok or out of memory, got exit=$($Result.Exit) out=$out"
}

$TextCrashSha = "37bf201c744f5e37e88463effb9d1c5e6e30d3b3"
Write-Output "phase fail-before textcat $TextCrashSha"
Restore-RuntimeFrom $TextCrashSha
$catSrc = Join-Path $Work "gc-textcat-nearfull-before.vire"
Set-TextcatKeep (Join-Path $Root "tests/native/gc-textcat-nearfull.vire") $catSrc 470
$beforeCat = Compile-Run "textcat-before" $catSrc
Write-Output "before_textcat exit=$($beforeCat.Exit) out=$($beforeCat.Out)"
if ($beforeCat.Out.Contains("crash ") -or $beforeCat.Out.Contains("textcat corrupt")) {
    Write-Output "FAIL_BEFORE textcat crash at $TextCrashSha keep=470"
} else {
    throw "fail-before textcat at $TextCrashSha expected crash, got exit=$($beforeCat.Exit) out=$($beforeCat.Out)"
}

Write-Output "phase pass-after textcat $AfterSha"
Restore-RuntimeFrom $AfterSha
for ($keep = 300; $keep -le 490; $keep++) {
    $src = Join-Path $Work "gc-textcat-$keep.vire"
    Set-TextcatKeep (Join-Path $Root "tests/native/gc-textcat-nearfull.vire") $src $keep
    $got = Compile-Run "textcat-$keep" $src
    Write-Output "after_textcat keep=$keep exit=$($got.Exit) out=$($got.Out)"
    Assert-TextcatClosed $got $keep "pass-after"
}
Write-Output "PASS_AFTER textcat keep 300..490 fail-closed at $AfterSha"

function Set-Keep {
    param([string]$Src, [string]$Dst, [int]$Keep)
    $text = [IO.File]::ReadAllText($Src)
    $updated = $text.Replace("while n < 470", "while n < $Keep")
    [IO.File]::WriteAllText($Dst, $updated)
}

function Assert-NearfullClosed {
    param($Result, [string]$Kind, [int]$Keep, [string]$Phase)
    $out = "$($Result.Out)"
    if ($out.Contains("$Kind corrupt") -or $out.Contains("crash ")) {
        throw "$Phase $Kind keep=$Keep crash/corrupt exit=$($Result.Exit) out=$out"
    }
    if ($Result.Exit -eq 0 -and $out.Contains("$Kind ok")) { return }
    if ($Result.Exit -eq 1 -and $out.Contains("out of memory")) { return }
    throw "$Phase $Kind keep=$Keep expected ok or out of memory, got exit=$($Result.Exit) out=$out"
}

$StaleSha = "8f07846"
Write-Output "phase fail-before replace/hex/take_arg $StaleSha"
Restore-RuntimeFrom $StaleSha
$repSrc = Join-Path $Work "gc-replace-nearfull-before.vire"
Set-Keep (Join-Path $Root "tests/native/gc-replace-nearfull.vire") $repSrc 470
$beforeRep = Compile-Run "replace-before" $repSrc
Write-Output "before_replace exit=$($beforeRep.Exit) out=$($beforeRep.Out)"
if ($beforeRep.Out.Contains("crash ") -or $beforeRep.Out.Contains("replace corrupt")) {
    Write-Output "FAIL_BEFORE replace crash at $StaleSha keep=470"
} else {
    throw "fail-before replace at $StaleSha expected crash, got exit=$($beforeRep.Exit) out=$($beforeRep.Out)"
}
$hexSrc = Join-Path $Work "gc-hex-nearfull-before.vire"
Set-Keep (Join-Path $Root "tests/native/gc-hex-nearfull.vire") $hexSrc 470
$beforeHex = Compile-Run "hex-before" $hexSrc
Write-Output "before_hex exit=$($beforeHex.Exit) out=$($beforeHex.Out)"
if ($beforeHex.Out.Contains("crash ") -or $beforeHex.Out.Contains("hex corrupt")) {
    Write-Output "FAIL_BEFORE hex crash at $StaleSha keep=470"
} else {
    throw "fail-before hex at $StaleSha expected crash, got exit=$($beforeHex.Exit) out=$($beforeHex.Out)"
}
$argSrc = Join-Path $Work "gc-takearg-nearfull-before.vire"
Set-Keep (Join-Path $Root "tests/native/gc-takearg-nearfull.vire") $argSrc 470
$beforeArg = Compile-Run "takearg-before" $argSrc
Write-Output "before_take_arg exit=$($beforeArg.Exit) out=$($beforeArg.Out)"
if ($beforeArg.Out.Contains("crash ") -or $beforeArg.Out.Contains("take_arg corrupt")) {
    Write-Output "FAIL_BEFORE take_arg crash at $StaleSha keep=470"
} else {
    throw "fail-before take_arg at $StaleSha expected crash, got exit=$($beforeArg.Exit) out=$($beforeArg.Out)"
}

Write-Output "phase pass-after replace/hex/take_arg $AfterSha"
Restore-RuntimeFrom $AfterSha
$kinds = @(
    @{ Name = "replace"; Src = "tests/native/gc-replace-nearfull.vire"; Kind = "replace" },
    @{ Name = "hex"; Src = "tests/native/gc-hex-nearfull.vire"; Kind = "hex" },
    @{ Name = "take_arg"; Src = "tests/native/gc-takearg-nearfull.vire"; Kind = "take_arg" }
)
foreach ($k in $kinds) {
    for ($keep = 300; $keep -le 490; $keep++) {
        $src = Join-Path $Work ("gc-" + $k.Name + "-$keep.vire")
        Set-Keep (Join-Path $Root $k.Src) $src $keep
        $got = Compile-Run ($k.Name + "-$keep") $src
        Write-Output ("after_" + $k.Name + " keep=$keep exit=$($got.Exit) out=$($got.Out)")
        Assert-NearfullClosed $got $k.Kind $keep "pass-after"
    }
    Write-Output ("PASS_AFTER " + $k.Name + " keep 300..490 fail-closed at $AfterSha")
}
$splitNp = Compile-Run "split-nopressure" (Join-Path $Root "tests/native/gc-split-nopressure.vire")
Write-Output "after_split_nopressure exit=$($splitNp.Exit) out=$($splitNp.Out)"
if ($splitNp.Exit -ne 0 -or "$($splitNp.Out)" -notmatch "split ok") {
    throw "pass-after split nopressure expected split ok, got exit=$($splitNp.Exit) out=$($splitNp.Out)"
}
Write-Output "PASS_AFTER split nopressure at $AfterSha"
$extraKinds = @(
    @{ Name = "split"; Src = "tests/native/gc-split-nearfull.vire"; Kind = "split" },
    @{ Name = "to_text"; Src = "tests/native/gc-to_text-nearfull.vire"; Kind = "to_text" },
    @{ Name = "add"; Src = "tests/native/gc-add-nearfull.vire"; Kind = "add" },
    @{ Name = "keys"; Src = "tests/native/gc-keys-nearfull.vire"; Kind = "keys" },
    @{ Name = "extend"; Src = "tests/native/gc-extend-nearfull.vire"; Kind = "extend" }
)
foreach ($k in $extraKinds) {
    foreach ($keep in @(300, 470, 478, 482, 490)) {
        $src = Join-Path $Work ("gc-" + $k.Name + "-$keep.vire")
        Set-Keep (Join-Path $Root $k.Src) $src $keep
        $got = Compile-Run ($k.Name + "-$keep") $src
        Write-Output ("after_" + $k.Name + " keep=$keep exit=$($got.Exit) out=$($got.Out)")
        Assert-NearfullClosed $got $k.Kind $keep "pass-after"
    }
    Write-Output ("PASS_AFTER " + $k.Name + " keep 300,470,478,482,490 fail-closed at $AfterSha")
}

Write-Output "native gc/loop proof ok"
Write-Output "note: a truly infinite accept loop is not shown in CI; ticks/rt_note_wait reset the 2e6 spin counter per turn, then this job shuts down after 2.5e6 counted trips."
exit 0
