# FAIL_BEFORE / PASS_AFTER for else-if binding. Real PE on Windows.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$BaseSha = (git rev-parse origin/native-compiler).Trim()
$AfterSha = (git rev-parse HEAD).Trim()
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $Root "tests/native/else-if-bind.vire") (Join-Path $Data "else-if-bind.vire") -Force
$Want = "params`ntwo`none`nzero`none`nbig`ntwo`nother"

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

$Work = Join-Path $env:TEMP ("vire-else-if-" + [guid]::NewGuid().ToString("n"))
git worktree add --detach $Work $BaseSha
Push-Location $Work
dotnet build vire.csproj -c Release -nologo
$baseDll = Join-Path $Work "bin/Release/net10.0/vire.dll"
$before = & dotnet exec $baseDll (Join-Path $Root "data/else-if-bind.vire") 2>&1 | Out-String
$beforeCode = $LASTEXITCODE
Pop-Location
Write-Output $before
if ($beforeCode -eq 0) { throw "expected base host to fail else-if steal program" }
if ($before -notmatch "line does not start a statement") { throw "expected steal parse error at base" }
Write-Output ("FAIL_BEFORE at " + $BaseSha + ": nested if inside else-if stole chain else/end -> line does not start a statement")
git worktree remove --force $Work

$hostOut = & dotnet exec $VireDll "data/else-if-bind.vire"
$hostCode = $LASTEXITCODE
Write-Output $hostOut
if ($hostCode -ne 0) { throw "host else-if-bind exit $hostCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r', '').Trim()
$wantNorm = ($Want -replace '\r', '').Trim()
if ($hostNorm -ne $wantNorm) { throw "host stdout mismatch" }

$comp = & dotnet exec $VireDll --compiler compile-native.vire data/else-if-bind.vire data/else-if-bind.hex
Write-Output $comp
if ($LASTEXITCODE -ne 0) { throw "compile else-if-bind" }
if ("$comp" -notmatch "compiled") { throw "compile-native missing compiled" }
$exe = Join-Path $Data "else-if-bind.exe"
Convert-HexToExe (Join-Path $Root "data/else-if-bind.hex") $exe
$peOut = & $exe
$peCode = $LASTEXITCODE
Write-Output $peOut
if ($peCode -ne 0) { throw "PE else-if-bind exit $peCode" }
$peNorm = (($peOut | Out-String) -replace '\r', '').Trim()
if ($hostNorm -ne $peNorm) { throw "host and PE stdout differ" }
Write-Output "host_pe_match else-if-bind"
Write-Output ("PASS_AFTER at " + $AfterSha + ": host and gen1 PE identical for if/else-if/else, nested if, else-if in define")
Write-Output "else-if windows check ok"
