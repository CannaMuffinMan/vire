# Compile two small programs with compile-native.vire: one that uses a
# sibling file, and one that needs deps/<name>/lib.vire. Compare the native
# exe stdout to the interpreter. Sources live under checks/native-deps and
# are copied under data/ so read/write stay in the writable zone.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-deps"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null
Copy-Item -Recurse (Join-Path $Root "checks/native-deps/*") $Work

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

$programs = @(
    @{ Name = "use-main"; Want = "from use" },
    @{ Name = "need-main"; Want = "from need" }
)

$failed = $false
foreach ($program in $programs) {
    $src = Join-Path $Work ($program.Name + ".vire")
    $interp = Invoke-Vire $src
    if ($interp.Code -ne 0 -or $interp.Text -ne $program.Want) {
        Write-Output "FAIL interpret $($program.Name) exit=$($interp.Code) got=$($interp.Text)"
        $failed = $true
        continue
    }
    $srcRel = "data/native-deps/" + $program.Name + ".vire"
    $hexRel = "data/native-deps/" + $program.Name + ".hex"
    $compiled = Invoke-Vire compile-native.vire $srcRel $hexRel
    if ($compiled.Code -ne 0) {
        Write-Output "FAIL compile $($program.Name) exit=$($compiled.Code) $($compiled.Text)"
        $failed = $true
        continue
    }
    $hex = [System.IO.File]::ReadAllText((Join-Path $Root $hexRel)).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    $exePath = Join-Path $Work ($program.Name + ".exe")
    [System.IO.File]::WriteAllBytes($exePath, $bytes)
    $got = & $exePath 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $got = $got.Trim()
    if ($got -eq $program.Want -and $exit -eq 0) {
        Write-Output "PASS $($program.Name)"
        continue
    }
    Write-Output "FAIL run $($program.Name) exit=$exit got=$got want=$($program.Want)"
    $failed = $true
}

$bad = Join-Path $Work "bad-lock"
New-Item -ItemType Directory -Force -Path (Join-Path $bad "deps\kit") | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $bad "deps\kit\lib.vire"), "define kitWord`n  return `"tampered`"`nend`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $bad "app.vire"), "need `"kit`"`n`ndefine main`n  say kitWord`nend`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $bad "deps.lock"), ("kit " + ("ab" * 32) + "`n"), $utf8)
$badCompile = Invoke-Vire compile-native.vire "data/native-deps/bad-lock/app.vire" "data/native-deps/bad-lock/app.hex"
if ($badCompile.Code -eq 0 -or -not $badCompile.Text.Contains("deps.lock does not match")) {
    Write-Output "FAIL bad lock was compiled exit=$($badCompile.Code) $($badCompile.Text)"
    $failed = $true
} else {
    Write-Output "PASS bad lock refused"
}

if ($failed) { exit 1 }
Write-Output "native deps ok"
exit 0
