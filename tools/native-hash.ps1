# Compile a tiny program that uses hash, run the exe, and match SHA-256.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-hash"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null

$src = @"
define main
  say (hash with "")
  say (hash with "abc")
  say (hash with "hello")
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

$code = Invoke-Vire compile-native.vire "data/native-hash/app.vire" "data/native-hash/app.hex"
if ($code -ne 0) { Write-Output "FAIL compile exit=$code"; exit 1 }
$hexPath = Join-Path $Work "app.hex"
$exePath = Join-Path $Work "app.exe"
$hex = [System.IO.File]::ReadAllText($hexPath).Trim()
$bytes = New-Object byte[] ($hex.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
}
[System.IO.File]::WriteAllBytes($exePath, $bytes)
$gotLines = @(& $exePath 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
$exit = $LASTEXITCODE
$wantLines = @(
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
)
$got = $gotLines -join "`n"
$want = $wantLines -join "`n"
if (($gotLines -join "|") -eq ($wantLines -join "|") -and $exit -eq 0) {
    Write-Output "PASS hash"
    exit 0
}
Write-Output "FAIL run exit=$exit got=$got want=$want"
exit 1
