# Fail-closed native heap checks. A list that outgrows the 32MB bump arena,
# and a read larger than the arena but under the 1_000_000 byte cap, must
# print "out of memory" and exit 1 instead of writing past VirtualAlloc.
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
    Copy-Item $Src (Join-Path $Root $srcRel)
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

function Assert-Oom {
    param([string]$Name, [string]$Exe)
    $got = ""
    $exit = 0
    try {
        $got = (& $Exe 2>&1 | Out-String)
        $exit = $LASTEXITCODE
    } catch {
        $got = $_.ToString()
        $exit = $LASTEXITCODE
    }
    $got = "$got".Trim()
    if ($exit -eq 1 -and $got.Contains("out of memory") -and -not $got.Contains("ok")) {
        Write-Output "PASS $Name"
        return
    }
    Write-Output "FAIL $Name exit=$exit got=$got"
    exit 1
}

$sayExe = Compile-Native "say-list" (Join-Path $Root "tests/native/say-list.vire")
$say = (& $sayExe 2>&1 | Out-String).Trim()
$sayExit = $LASTEXITCODE
$want = "[a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]"
if ($sayExit -ne 0 -or $say -ne $want) {
    Write-Output "FAIL say-list exit=$sayExit got=$say"
    exit 1
}
Write-Output "PASS say-list"

Assert-Oom "oom-list" (Compile-Native "oom-list" (Join-Path $Root "tests/native/oom-list.vire"))
Assert-Oom "oom-read" (Compile-Native "oom-read" (Join-Path $Root "tests/native/oom-read.vire"))
Write-Output "native oom ok"
exit 0
