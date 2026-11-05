# Compile a 400-line multi-file program that needs one deps package.
# Compare the native exe to the interpreter. Sources are written under data/
# so compile-native.vire can read them. Fails if the compiler exceeds
# VIRE_BUDGET (5000000) or the exe does not match.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-large"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path (Join-Path $Work "deps/kit") -Force | Out-Null

$utf8 = New-Object System.Text.UTF8Encoding $false
$nums = (1..30 | ForEach-Object { [string]$_ }) -join ", "
$rows = New-Object System.Collections.Generic.List[string]
$n = 0
while ($rows.Count -lt 400) {
    $n++
    $rows.Add("define row$n")
    $rows.Add("  return [$nums]")
    $rows.Add("end")
}
$rowsBody = ($rows -join "`n") + "`n"
[System.IO.File]::WriteAllText((Join-Path $Work "rows.vire"), $rowsBody, $utf8)
if ($rows.Count -lt 400) { Write-Output "FAIL fixture has $($rows.Count) lines"; exit 1 }

$app = "need `"kit`"`nuse `"rows.vire`"`n`ndefine main`n  say (text with ((length with (row1)) + (kitWord)))`nend`n"
[System.IO.File]::WriteAllText((Join-Path $Work "app.vire"), $app, $utf8)
$lib = "define kitWord`n  return 7`nend`n"
[System.IO.File]::WriteAllText((Join-Path $Work "deps/kit/lib.vire"), $lib, $utf8)
$sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($lib))
$hexHash = -join ($sha | ForEach-Object { $_.ToString("x2") })
[System.IO.File]::WriteAllText((Join-Path $Work "deps.lock"), "kit $hexHash`n", $utf8)

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
$VireExe = Join-Path $Root "bin/Release/net10.0/vire.exe"
function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    if (Test-Path $VireExe) { $out = & $VireExe @Args }
    else { $out = & dotnet exec $VireDll @Args }
    $code = $LASTEXITCODE
    $text = ""
    if ($null -ne $out) {
        if ($out -is [System.Array]) { $text = ($out | ForEach-Object { [string]$_ }) -join "`n" }
        else { $text = [string]$out }
    }
    return @{ Code = [int]$code; Text = $text.Trim() }
}

$want = "37"
$interp = Invoke-Vire "data/native-large/app.vire"
if ($interp.Code -ne 0 -or $interp.Text -ne $want) {
    Write-Output "FAIL interpret exit=$($interp.Code) got=$($interp.Text)"
    exit 1
}
$compiled = Invoke-Vire compile-native.vire "data/native-large/app.vire" "data/native-large/app.hex"
if ($compiled.Code -ne 0) {
    Write-Output "FAIL compile exit=$($compiled.Code) $($compiled.Text)"
    exit 1
}
$hex = [System.IO.File]::ReadAllText((Join-Path $Work "app.hex")).Trim()
$bytes = New-Object byte[] ($hex.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
}
$exePath = Join-Path $Work "app.exe"
[System.IO.File]::WriteAllBytes($exePath, $bytes)
$got = & $exePath 2>&1 | Out-String
$exit = $LASTEXITCODE
$got = $got.Trim()
if ($got -ne $want -or $exit -ne 0) {
    Write-Output "FAIL run exit=$exit got=$got want=$want"
    exit 1
}
Write-Output "PASS native-large lines=$($rows.Count)"
exit 0
