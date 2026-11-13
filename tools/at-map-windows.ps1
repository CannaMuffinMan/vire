# FAIL_BEFORE / PASS_AFTER: string-keyed `at` on maps. Real PE on Windows.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$BaseSha = "3946d1c6c4f3fc12e4a486da600bba354ad60c64"
$AfterSha = (git rev-parse HEAD).Trim()
git cat-file -t $BaseSha 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { git fetch origin $BaseSha 2>&1 | Out-Host }
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $Root "tests/native/at-map.vire") (Join-Path $Data "at-map.vire") -Force
Copy-Item (Join-Path $Root "tests/native/at-none.vire") (Join-Path $Data "at-none.vire") -Force
$Want = "ada`ntrue`n42"

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

$Work = Join-Path $env:TEMP ("vire-at-map-" + [guid]::NewGuid().ToString("n"))
git worktree add --detach $Work $BaseSha
Push-Location $Work
dotnet build vire.csproj -c Release -nologo
Copy-Item (Join-Path $Root "tests/native/at-map.vire") (Join-Path $Work "data/at-map.vire") -Force
$saved = $env:VIRE_BUDGET
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
& dotnet exec (Join-Path $Work "bin/Release/net10.0/vire.dll") --compiler compile-native.vire data/at-map.vire data/at-map.hex
if ($saved) { $env:VIRE_BUDGET = $saved }
Convert-HexToExe (Join-Path $Work "data/at-map.hex") (Join-Path $Work "data/at-map.exe")
$beforeOut = & (Join-Path $Work "data/at-map.exe") 2>&1 | Out-String
$beforeCode = $LASTEXITCODE
Pop-Location
Write-Output $beforeOut
$beforeNorm = ($beforeOut -replace '\r', '').Trim()
$wantNorm = ($Want -replace '\r', '').Trim()
if ($beforeCode -eq 0 -and $beforeNorm -eq $wantNorm) { throw "expected base PE to disagree on u at id" }
if ($beforeOut -notmatch "an index must be a whole number") { throw "expected FAIL_BEFORE at $BaseSha to print an index must be a whole number" }
Write-Output ("FAIL_BEFORE at " + $BaseSha + ": gen1 PE split/at for u at `"id`" disagreed with host")
git worktree remove --force $Work

$hostOut = & dotnet exec $VireDll "data/at-map.vire"
$hostCode = $LASTEXITCODE
Write-Output $hostOut
if ($hostCode -ne 0) { throw "host at-map exit $hostCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $wantNorm) { throw "host at-map stdout" }

Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
& dotnet exec $VireDll --compiler compile-native.vire data/at-map.vire data/at-map.hex
if ($saved) { $env:VIRE_BUDGET = $saved }
$exe = Join-Path $Data "at-map.exe"
Convert-HexToExe (Join-Path $Root "data/at-map.hex") $exe
$peOut = & $exe
$peCode = $LASTEXITCODE
Write-Output $peOut
if ($peCode -ne 0) { throw "PE at-map exit $peCode" }
$peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $peNorm) { throw "host and PE stdout differ for at-map" }
Write-Output "host_pe_match at-map"

$hostNone = & dotnet exec $VireDll "data/at-none.vire" 2>&1 | Out-String
Write-Output $hostNone
if ($hostNone -notmatch "at needs a list, text, or map") { throw "host none-at message" }
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
& dotnet exec $VireDll --compiler compile-native.vire data/at-none.vire data/at-none.hex
if ($saved) { $env:VIRE_BUDGET = $saved }
Convert-HexToExe (Join-Path $Root "data/at-none.hex") (Join-Path $Data "at-none.exe")
$peNone = & (Join-Path $Data "at-none.exe") 2>&1 | Out-String
Write-Output $peNone
if ($peNone -notmatch "at needs a list, text, or map") { throw "PE none-at message" }
Write-Output "host_pe_match at-none"

Write-Output ("PASS_AFTER at " + $AfterSha + ": host and gen1 PE identical for map at string keys; none-at same error")
Write-Output "at-map windows check ok"
