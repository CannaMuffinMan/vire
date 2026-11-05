# Native try/miss and for. Compiles the two programs under data/native-forms
# with compile-native.vire, runs the exe, and matches the interpreter.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-forms"
if (-not (Test-Path $Work)) { throw "missing data/native-forms" }

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
$VireExe = Join-Path $Root "bin/Release/net10.0/vire.exe"
function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    if (Test-Path $VireExe) { $out = & $VireExe @Args }
    else { $out = & dotnet exec $VireDll @Args }
    $code = $LASTEXITCODE
    if ($null -ne $out) { $out | Write-Host }
    if ($null -eq $code) { return 0 }
    return [int]$code
}

$programs = @("try-miss", "for-list")

$failed = $false
foreach ($program in $programs) {
    $srcRel = "data/native-forms/" + $program + ".vire"
    $hexRel = "data/native-forms/" + $program + ".hex"
    $code = Invoke-Vire compile-native.vire $srcRel $hexRel
    if ($code -ne 0) {
        Write-Output "FAIL compile $program exit=$code"
        $failed = $true
        continue
    }
    $hexPath = Join-Path $Root $hexRel
    $exePath = Join-Path $Work ($program + ".exe")
    $hex = [System.IO.File]::ReadAllText($hexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($exePath, $bytes)
    $got = & $exePath 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $got = $got.Trim()
    if (Test-Path $VireExe) { $wantRaw = & $VireExe $srcRel }
    else { $wantRaw = & dotnet exec $VireDll $srcRel }
    $wantCode = $LASTEXITCODE
    $want = ($wantRaw | Out-String).Trim()
    if ($wantCode -ne 0) {
        Write-Output "FAIL interpret $program exit=$wantCode"
        $failed = $true
        continue
    }
    if ($got -eq $want -and $exit -eq 0) {
        Write-Output "PASS $program"
        continue
    }
    Write-Output "FAIL run $program exit=$exit got=$got want=$want"
    $failed = $true
}

if ($failed) { exit 1 }
Write-Output "native forms ok"
exit 0
