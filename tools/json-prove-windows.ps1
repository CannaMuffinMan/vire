# Host interpreter vs gen1 native PE for JSON decode/encode.
# Does not raise 32MB arena, 100000 list cap, or 5M step cap.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

$BaseSha = "9ea4561d12236f7f2f44858f137d7c948836df65"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

$wt = Join-Path $env:RUNNER_TEMP "vire-json-fail-before"
if (-not $env:RUNNER_TEMP) { $wt = Join-Path $env:TEMP "vire-json-fail-before" }
if (Test-Path $wt) { Remove-Item -Recurse -Force $wt }
git worktree add --detach $wt $BaseSha
Push-Location $wt
try {
    & dotnet build vire.csproj -c Release -o (Join-Path $wt "out")
    if ($LASTEXITCODE -ne 0) { throw "base build failed" }
    $beforeSrc = @(
        'define main',
        '  let row be parse with "[01]"',
        '  say "FAIL_BEFORE parse accepted [01] as " + (text with (row at 0)) + " at 9ea4561d12236f7f2f44858f137d7c948836df65"',
        'end'
    )
    Set-Content -Path (Join-Path $wt "json-fail-before.vire") -Value $beforeSrc
    $beforeDll = Join-Path $wt "out/vire.dll"
    $beforeOut = & dotnet exec $beforeDll json-fail-before.vire
    $beforeCode = $LASTEXITCODE
    Write-Output $beforeOut
    Write-Output "json_fail_before_exit $beforeCode"
    if ($beforeCode -ne 0) { throw "fail-before parse guest exit $beforeCode" }
    if ("$beforeOut" -notmatch "FAIL_BEFORE parse accepted") { throw "missing FAIL_BEFORE line" }
    if (Test-Path (Join-Path $wt "src/rt-json.vire")) { throw "base already has rt-json.vire" }
} finally {
    Pop-Location
    git worktree remove --force $wt
}
Write-Output "FAIL_BEFORE at ${BaseSha}: builtin parse accepted [01]; src/rt-json.vire absent"

Write-Output "json_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostOut = & dotnet exec $VireDll json-prove.vire
$code = $LASTEXITCODE
$sw.Stop()
Write-Output $hostOut
Write-Output "json_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "json_host_exit $code"
if ($code -ne 0) { throw "host json-prove exit $code" }
if ("$hostOut" -notmatch "JSON PROVE pass") { throw "host json-prove missing pass" }
if ("$hostOut" -notmatch "y_string_surrogate enc PASS") { throw "missing surrogate encode" }
if ("$hostOut" -notmatch "n_number_leading_zero REJECT") { throw "missing leading-zero reject" }
if ("$hostOut" -notmatch "schema_check PASS") { throw "missing schema_check" }
if ("$hostOut" -notmatch "FUZZ seed 20261113 PASS") { throw "missing fuzz" }
Write-Output "PASS_AFTER host json-prove"

$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$lib = Get-Content -Raw (Join-Path $Root "src/rt-json.vire")
$schema = Get-Content -Raw (Join-Path $Root "src/rt-schema.vire")
$prove = Get-Content -Raw (Join-Path $Root "json-prove.vire")
$prove = $prove -replace '(?m)^use "src/rt-json.vire"\s*', ''
$prove = $prove -replace '(?m)^use "src/rt-schema.vire"\s*', ''
Set-Content -Path (Join-Path $Data "json-prove.vire") -Value ($lib + "`n" + $schema + "`n" + $prove) -NoNewline
$hexRel = "data/json-prove.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$compileOut = & dotnet exec $VireDll --compiler compile-native.vire data/json-prove.vire $hexRel
$compileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $compileOut
Write-Output "json_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "json_pe_compile_exit $compileCode"
if ($compileCode -ne 0) { throw "compile-native json-prove exit $compileCode" }
if ("$compileOut" -notmatch "compiled") { throw "compile-native missing compiled" }

$exe = Join-Path $Data "json-prove.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$peBytes = [System.IO.File]::ReadAllBytes($exe)
$ascii = [System.Text.Encoding]::ASCII.GetString($peBytes).ToLowerInvariant()
if ($ascii.Contains("ws2_32.dll")) { throw "json PE imported Winsock" }
Write-Output "json pe imports no Winsock"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peOut = & $exe
$peCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peOut
Write-Output "json_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "json_pe_exit $peCode"
if ($peCode -ne 0) { throw "json PE exit $peCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
$peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE stdout differ"
}
Write-Output "json host pe match"
Write-Output "PASS_AFTER host and gen1 PE json outputs identical at $AfterSha"
Write-Output "json windows prove ok"
