# Native compiler smoke on Windows. Compiles hello plus every tests/native
# fixture, turns the hex into an .exe, and checks the process exits cleanly
# with the interpreter's error text (never a crash).
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

function Get-NativeWant {
    param([string]$Path)
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line.StartsWith("~ native-error: ")) {
            return @{ Code = 1; Text = $line.Substring("~ native-error: ".Length).Trim(); Exact = $false }
        }
        if ($line.StartsWith("~ native-ok: ")) {
            return @{ Code = 0; Text = $line.Substring("~ native-ok: ".Length).Trim(); Exact = $true }
        }
    }
    return $null
}

$programs = @(
    @{ Name = "hello"; Src = "samples/hello.vire"; Want = "hello from vire"; Code = 0; Exact = $true }
)
foreach ($path in Get-ChildItem -LiteralPath (Join-Path $Root "tests/native") -Filter "*.vire") {
    $meta = Get-NativeWant $path.FullName
    if ($null -eq $meta) { throw "missing native comment in $($path.Name)" }
    $programs += @{ Name = [IO.Path]::GetFileNameWithoutExtension($path.Name); Src = ("tests/native/" + $path.Name); Want = $meta.Text; Code = $meta.Code; Exact = $meta.Exact }
}

$failed = $false
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
    if ($null -eq $exit) { $exit = 0 }
    $got = $got.Trim()
    $ok = $false
    if ($program.Exact) {
        if ($got -eq $program.Want -and $exit -eq $program.Code) { $ok = $true }
    }
    else {
        if ($got.Contains($program.Want) -and $exit -eq $program.Code) { $ok = $true }
    }
    if ($ok) {
        Write-Output "PASS $($program.Name)"
        continue
    }
    Write-Output "FAIL run $($program.Name) exit=$exit wantExit=$($program.Code) got=$got"
    $failed = $true
}

if ($failed) { exit 1 }
Write-Output "native smoke ok"
exit 0
