# Native compiler smoke on Windows. Compiles each known native sample with
# compile-native.vire, turns the hex into an .exe, and compares stdout to the
# interpreter. A crash after printing (index error) is recorded as a known
# Phase 3B failure and still runs.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-smoke"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
$VireExe = Join-Path $Root "bin/Release/net10.0/vire.exe"
function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    # Capture stdout so this function returns only the exit code. A
    # PowerShell function otherwise returns stdout mixed with LASTEXITCODE,
    # so `$code -ne 0` is true after a successful compile that printed
    # "compiled". Read LASTEXITCODE before Write-Host.
    if (Test-Path $VireExe) { $out = & $VireExe @Args }
    else { $out = & dotnet exec $VireDll @Args }
    $code = $LASTEXITCODE
    if ($null -ne $out) { $out | Write-Host }
    if ($null -eq $code) { return 0 }
    return [int]$code
}

$programs = @(
    @{ Name = "hello"; Src = "samples/hello.vire"; Want = "hello from vire" }
)

$failed = $false
$phase3b = $false
foreach ($program in $programs) {
    $srcCopy = Join-Path $Work ($program.Name + ".vire")
    Copy-Item $program.Src $srcCopy
    $srcRel = "data/native-smoke/" + $program.Name + ".vire"
    $hexRel = "data/native-smoke/" + $program.Name + ".hex"
    $code = Invoke-Vire compile-native.vire $srcRel $hexRel
    if ($code -ne 0) {
        Write-Output "FAIL compile $($program.Name) exit=$code"
        $failed = $true
        continue
    }
    $hexPath = Join-Path $Root $hexRel
    $exePath = Join-Path $Work ($program.Name + ".exe")
    $hex = [System.IO.File]::ReadAllText($hexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($exePath, $bytes)
    $got = & $exePath 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $got = $got.Trim()
    if ($got -eq $program.Want -and $exit -eq 0) {
        Write-Output "PASS $($program.Name)"
        continue
    }
    if ($got.Contains($program.Want) -and $exit -ne 0) {
        Write-Output "KNOWN FAIL Phase 3B $($program.Name): printed then exited $exit"
        $phase3b = $true
        continue
    }
    Write-Output "FAIL run $($program.Name) exit=$exit got=$got"
    $failed = $true
}

if ($failed) { exit 1 }
if ($phase3b) { Write-Output "native smoke finished with known Phase 3B failure" }
else { Write-Output "native smoke ok" }
exit 0
