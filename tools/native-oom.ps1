# Fail-closed native heap checks. A list that outgrows the 32MB bump arena,
# and repeated 800000-byte reads (under the 1_000_000 byte cap) that exhaust
# the remaining arena, must print "out of memory" and exit 1 instead of
# writing RX .text or past VirtualAlloc.
# Fail-before (native-windows job 131039507932, SHAs 7c7c8ea3 and c8ec7712):
#   FAIL oom-read exit=1 got=crash rip=00000001400051f7
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-oom"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null
$blobDir = Join-Path $Root "data"
if (-not (Test-Path $blobDir)) { New-Item -ItemType Directory -Path $blobDir | Out-Null }
$blob = Join-Path $blobDir "oom-blob.bin"
[System.IO.File]::WriteAllBytes($blob, (New-Object byte[] 800000))

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $out = & dotnet exec $VireDll @Args
    $code = $LASTEXITCODE
    if ($null -ne $out) { $out | Write-Host }
    if ($null -eq $code) { return 0 }
    return [int]$code
}

function Compile-Native {
    param([string]$Name, [string]$Src)
    $srcRel = "data/native-oom/$Name.vire"
    $hexRel = "data/native-oom/$Name.hex"
    Copy-Item $Src (Join-Path $Root $srcRel) -Force
    $code = Invoke-Vire compile-native.vire $srcRel $hexRel
    if ($code -ne 0) { throw "compile $Name failed exit=$code" }
    $hex = [System.IO.File]::ReadAllText((Join-Path $Root $hexRel)).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    $exe = Join-Path $Work "$Name.exe"
    [System.IO.File]::WriteAllBytes($exe, $bytes)
    return $exe
}

function Run-Exe {
    param([string]$Exe)
    $got = ""
    $exit = 0
    try {
        $got = (& $Exe 2>&1 | Out-String)
        $exit = $LASTEXITCODE
    } catch {
        $got = $_.ToString()
        $exit = $LASTEXITCODE
    }
    return @{ Exit = [int]$exit; Out = "$got".Trim() }
}

function Assert-Oom {
    param([string]$Name, [string]$Exe)
    $r = Run-Exe $Exe
    if ($r.Exit -eq 1 -and $r.Out.Contains("out of memory") -and -not $r.Out.Contains("ok") -and -not $r.Out.Contains("crash rip=")) {
        Write-Output "PASS $Name"
        return
    }
    Write-Output "FAIL $Name exit=$($r.Exit) got=$($r.Out)"
    exit 1
}

function Restore-NativeFrom {
    param([string]$Sha)
    git checkout $Sha -- src/rt.vire src/rt-more.vire data/src/rt.vire data/src/rt-more.vire compile-native.vire data/compile-native.vire
    if ($LASTEXITCODE -ne 0) { throw "checkout native sources from $Sha failed" }
}

function Ensure-Commit {
    param([string]$Sha)
    git cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    git fetch --depth 1 origin $Sha
    git cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "missing commit $Sha" }
}

$AfterSha = (git rev-parse HEAD).Trim()
$FailShas = @("7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867", "c8ec7712ab7d7f081c70cf4028098f0c70744421")

Write-Output "phase fail-before"
foreach ($sha in $FailShas) {
    Ensure-Commit $sha
    Restore-NativeFrom $sha
    $before = Run-Exe (Compile-Native "oom-read-before-$sha" (Join-Path $Root "tests/native/read-small.vire"))
    Write-Output "fail_before_sha $sha exit=$($before.Exit) out=$($before.Out)"
    if ($before.Exit -eq 1 -and $before.Out.Contains("crash rip=")) {
        Write-Output "FAIL_BEFORE read-small/oom-read crash at $sha"
    } else {
        throw "fail-before expected crash rip= at $sha, got exit=$($before.Exit) out=$($before.Out)"
    }
}

Write-Output "phase pass-after $AfterSha"
Restore-NativeFrom $AfterSha

$sayExe = Compile-Native "say-list" (Join-Path $Root "tests/native/say-list.vire")
$say = Run-Exe $sayExe
$want = "[a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]"
if ($say.Exit -ne 0 -or $say.Out -ne $want) {
    Write-Output "FAIL say-list exit=$($say.Exit) got=$($say.Out)"
    exit 1
}
Write-Output "PASS say-list"

Assert-Oom "oom-list" (Compile-Native "oom-list" (Join-Path $Root "tests/native/oom-list.vire"))

$small = Run-Exe (Compile-Native "read-small" (Join-Path $Root "tests/native/read-small.vire"))
if ($small.Exit -ne 0 -or $small.Out -ne "800000") {
    Write-Output "FAIL read-small exit=$($small.Exit) got=$($small.Out)"
    exit 1
}
Write-Output "PASS read-small"

Assert-Oom "oom-read" (Compile-Native "oom-read" (Join-Path $Root "tests/native/oom-read.vire"))
Write-Output "PASS_AFTER oom-read at $AfterSha"
Write-Output "native oom ok"
exit 0
