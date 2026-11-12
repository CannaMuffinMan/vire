# Host interpreter vs gen1 native PE for guest JSON schema checks.
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

$BaseSha = "d89edb29743c580613816d19cb1e7c749bce71e6"
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $((git rev-parse HEAD).Trim())"

$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$beforeLines = @(
    'define main',
    '  let row be parse with "{\"ok\":1}"',
    '  say "FAIL_BEFORE parse accepted {\"ok\":1} kind=" + (kind with (row at "ok")) + " at d89edb29743c580613816d19cb1e7c749bce71e6"',
    'end'
)
Set-Content -Path (Join-Path $Data "schema-fail-before.vire") -Value $beforeLines
$beforeOut = & dotnet exec $VireDll data/schema-fail-before.vire
$beforeCode = $LASTEXITCODE
Write-Output $beforeOut
Write-Output "schema_fail_before_exit $beforeCode"
if ($beforeCode -ne 0) { throw "fail-before parse guest exit $beforeCode" }
if ("$beforeOut" -notmatch "FAIL_BEFORE parse accepted") { throw "missing FAIL_BEFORE line" }
if ("$beforeOut" -notmatch "kind=number") { throw "fail-before expected kind=number" }

Write-Output "schema_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostOut = & dotnet exec $VireDll schema-prove.vire
$code = $LASTEXITCODE
$sw.Stop()
Write-Output $hostOut
Write-Output "schema_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "schema_host_exit $code"
if ($code -ne 0) { throw "host schema-prove exit $code" }
if ("$hostOut" -notmatch "SCHEMA PROVE pass") { throw "host schema-prove missing pass" }
if ("$hostOut" -notmatch "TYPE mismatch REJECT") { throw "missing type mismatch reject" }
if ("$hostOut" -notmatch "MISSING required REJECT") { throw "missing required reject" }
if ("$hostOut" -notmatch "UNKNOWN field REJECT") { throw "missing unknown field reject" }
if ("$hostOut" -notmatch "OVERSIZE string REJECT") { throw "missing oversize string reject" }
if ("$hostOut" -notmatch "OVERSIZE array REJECT") { throw "missing oversize array reject" }
if ("$hostOut" -notmatch "ADV too-deep array REJECT") { throw "missing too-deep reject" }
if ("$hostOut" -notmatch "HEALTH valid PASS") { throw "missing health valid" }
Write-Output "PASS_AFTER host schema-prove"

$lib = Get-Content -Raw (Join-Path $Root "src/rt-schema.vire")
$prove = Get-Content -Raw (Join-Path $Root "schema-prove.vire")
$prove = $prove -replace '(?m)^use "src/rt-schema.vire"\s*', ''
Set-Content -Path (Join-Path $Data "schema-prove.vire") -Value ($lib + "`n" + $prove) -NoNewline
$hexRel = "data/schema-prove.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$compileOut = & dotnet exec $VireDll --compiler compile-native.vire data/schema-prove.vire $hexRel
$compileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $compileOut
Write-Output "schema_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "schema_pe_compile_exit $compileCode"
if ($compileCode -ne 0) { throw "compile-native schema-prove exit $compileCode" }
if ("$compileOut" -notmatch "compiled") { throw "compile-native missing compiled" }

$exe = Join-Path $Data "schema-prove.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$peBytes = [System.IO.File]::ReadAllBytes($exe)
$ascii = [System.Text.Encoding]::ASCII.GetString($peBytes).ToLowerInvariant()
if ($ascii.Contains("ws2_32.dll")) { throw "schema PE imported Winsock" }
Write-Output "schema pe imports no Winsock"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peOut = & $exe
$peCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peOut
Write-Output "schema_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "schema_pe_exit $peCode"
if ($peCode -ne 0) { throw "schema PE exit $peCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
$peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE stdout differ"
}
Write-Output "schema host pe match"
Write-Output "PASS_AFTER schema host and gen1 PE agree"
Write-Output "schema windows prove ok"
