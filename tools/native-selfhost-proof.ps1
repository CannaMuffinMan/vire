# Native PE self-host proof on Windows. Host-compile compile-native.vire
# with the C# runner, run the exe on hello-stage, then have that exe compile
# compile-native.vire again. Success is identical SHA-256 of the two hex
# files. Does not raise the 32MB arena.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-selfhost"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null

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

function Hex-ToExe {
    param([string]$HexPath, [string]$ExePath)
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $($HexPath)" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

Copy-Item (Join-Path $Root "compile-native.vire") (Join-Path $Work "compile-native.vire")
Copy-Item -Recurse (Join-Path $Root "src") (Join-Path $Work "src")
Copy-Item (Join-Path $Root "tests/native/hello-stage.vire") (Join-Path $Work "hello-stage.vire")

$code = Invoke-Vire compile-native.vire "data/native-selfhost/compile-native.vire" "data/native-selfhost/gen1.hex"
if ($code -ne 0) { Write-Output "FAIL host compile compile-native.vire exit=$code"; exit 1 }
Hex-ToExe (Join-Path $Work "gen1.hex") (Join-Path $Work "gen1.exe")

$helloOut = & (Join-Path $Work "gen1.exe") "data/native-selfhost/hello-stage.vire" "data/native-selfhost/hello-stage.hex" 2>&1 | Out-String
$helloCode = $LASTEXITCODE
$helloOut = $helloOut.Trim()
if ($helloCode -ne 0 -or $helloOut -notmatch "compiled") {
    Write-Output "FAIL gen1 compile hello-stage exit=$helloCode out=$helloOut"
    exit 1
}
Hex-ToExe (Join-Path $Work "hello-stage.hex") (Join-Path $Work "hello-stage.exe")
$stage = & (Join-Path $Work "hello-stage.exe") 2>&1 | Out-String
$stageCode = $LASTEXITCODE
$stage = $stage.Trim()
if ($stage -ne "hello from stage" -or $stageCode -ne 0) {
    Write-Output "FAIL hello-stage exit=$stageCode got=$stage"
    exit 1
}
Write-Output "PASS hello-stage"

$nativeOut = & (Join-Path $Work "gen1.exe") "data/native-selfhost/compile-native.vire" "data/native-selfhost/gen2.hex" 2>&1 | Out-String
$nativeCode = $LASTEXITCODE
$nativeOut = $nativeOut.Trim()
if ($nativeCode -ne 0 -or $nativeOut -notmatch "compiled") {
    Write-Output "FAIL native self-compile exit=$nativeCode out=$nativeOut"
    exit 1
}

$h1 = (Get-FileHash -Algorithm SHA256 (Join-Path $Work "gen1.hex")).Hash.ToLowerInvariant()
$h2 = (Get-FileHash -Algorithm SHA256 (Join-Path $Work "gen2.hex")).Hash.ToLowerInvariant()
Write-Output "gen1 $h1"
Write-Output "gen2 $h2"
if ($h1 -ne $h2) {
    Write-Output "FAIL native self-host hashes differ"
    exit 1
}
Write-Output "native selfhost ok"
exit 0
