# Compile a tiny program that uses replace, run the exe, and match the interpreter.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-replace"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null

$src = @"
define main
  say (replace with "a-b-a", "a", "c")
  say (replace with "aaa", "aa", "b")
  say (replace with "hi", "z", "q")
  say (replace with "ab", "b", "")
  say (replace with "", "a", "z")
  say (replace with "aba", "a", "aa")
end
"@
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $Work "app.vire"), $src, $utf8)

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

$code = Invoke-Vire compile-native.vire "data/native-replace/app.vire" "data/native-replace/app.hex"
if ($code -ne 0) { Write-Output "FAIL compile exit=$code"; exit 1 }
$hexPath = Join-Path $Work "app.hex"
$exePath = Join-Path $Work "app.exe"
$hex = [System.IO.File]::ReadAllText($hexPath).Trim()
$bytes = New-Object byte[] ($hex.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
}
[System.IO.File]::WriteAllBytes($exePath, $bytes)
$got = (& $exePath 2>&1 | Out-String).Trim()
$exit = $LASTEXITCODE
if (Test-Path $VireExe) { $wantRaw = & $VireExe "data/native-replace/app.vire" }
else { $wantRaw = & dotnet exec $VireDll "data/native-replace/app.vire" }
$wantCode = $LASTEXITCODE
$want = ($wantRaw | Out-String).Trim()
if ($wantCode -ne 0) { Write-Output "FAIL interpret exit=$wantCode"; exit 1 }
if ($got -eq $want -and $exit -eq 0) {
    Write-Output "PASS replace"
    exit 0
}
Write-Output "FAIL run exit=$exit got=$got want=$want"
exit 1
