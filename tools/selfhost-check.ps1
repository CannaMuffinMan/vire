# Stage-1/2/3 self-host check for compiler.vire.
# Real CLI:
#   dotnet exec vire.dll compiler.vire data/compiler.vire data/stage1.vc
#   dotnet exec vire.dll run data/stage1.vc compiler.vire stage2.vc
# Stage 2+ run with the .vc sandbox root = data/, so remaining args are
# relative to data/ (compiler.vire and stageN.vc names only).
# Seal: throwaway 32-byte key in VIRE_SEAL_KEY (base64). VC2 uses a random
# nonce, so this script compares unsealed payload SHA-256 via:
#   vire payload-sha256 data/stageN.vc
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$env:VIRE_SEAL_KEY = [Convert]::ToBase64String($bytes)
if (-not $env:VIRE_BUDGET) { $env:VIRE_BUDGET = "5000000" }
$Work = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Work | Out-Null
Copy-Item (Join-Path $Root "compiler.vire") (Join-Path $Work "compiler.vire") -Force
foreach ($name in @("stage1.vc", "stage2.vc", "stage3.vc")) {
    $path = Join-Path $Work $name
    if (Test-Path $path) { Remove-Item -Force $path }
}

$VireExe = Join-Path $Root "bin/Release/net10.0/vire.exe"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    if (Test-Path $VireDll) {
        & dotnet exec $VireDll @Args
    } elseif (Test-Path $VireExe) {
        & $VireExe @Args
    } else {
        & dotnet run --no-build -c Release --project (Join-Path $Root "vire.csproj") -- @Args
    }
    if ($LASTEXITCODE -ne 0) { throw "vire failed: $Args" }
}

Write-Output "stage 1: interpreter compiles compiler.vire"
Invoke-Vire compiler.vire data/compiler.vire data/stage1.vc
Write-Output "stage 2: stage1.vc compiles compiler.vire"
Invoke-Vire run data/stage1.vc compiler.vire stage2.vc
Write-Output "stage 3: stage2.vc compiles compiler.vire"
Invoke-Vire run data/stage2.vc compiler.vire stage3.vc

function Get-PayloadSha([string]$Path) {
    $out = Invoke-Vire payload-sha256 $Path
    if ($out -is [array]) { return $out[-1].ToString().Trim() }
    return $out.ToString().Trim()
}
$hash1 = Get-PayloadSha "data/stage1.vc"
$hash2 = Get-PayloadSha "data/stage2.vc"
$hash3 = Get-PayloadSha "data/stage3.vc"
Write-Output "stage1 $hash1"
Write-Output "stage2 $hash2"
Write-Output "stage3 $hash3"
if ($hash1 -ne $hash2 -or $hash2 -ne $hash3) {
    Write-Error "selfhost hashes differ"
    exit 1
}
Write-Output "selfhost ok"
