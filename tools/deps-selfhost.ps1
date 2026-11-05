# Prove compiler.vire can compile a program that needs deps/<name>/lib.vire,
# then a compiled copy of that compiler can compile the same program again.
# Sealed VC2 files use a random nonce, so this compares unsealed payloads
# (payload-sha256 and payload-write bytes), same as selfhost-check.ps1.
#
# Sandbox (do not weaken it):
#   Interpreter: sandbox root is the folder of compiler.vire (the repo).
#   read/write only succeed under data/ or site/.
#   Stage runs: `vire run data/<file>.vc` sets the sandbox root to data/.
#   Remaining args are relative to data/. A compiled program whose root is
#   data/ may read paths inside that root (RootIsDataOrSite).
# Repo-root deps/ is invisible to both. The layout is created under data/,
# the same way selfhost-check copies compiler.vire into data/.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path -LiteralPath $VireDll)) {
    & dotnet build -c Release --nologo
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
# Runtime name is VIRE_SEAL_KEY (32-byte key, base64). Throwaway, not a secret.
$env:VIRE_SEAL = [Convert]::ToBase64String($bytes)
$env:VIRE_SEAL_KEY = $env:VIRE_SEAL
$env:VIRE_BUDGET = "5000000"

$Work = Join-Path $Root "data"
$Pkg = "greet"
$DepDir = Join-Path $Work "deps/$Pkg"
New-Item -ItemType Directory -Force -Path $DepDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$lib = "define banner`n  return `"deps-selfhost-ok`"`nend`n"
$app = "need `"$Pkg`"`n`ndefine main`n  say banner`nend`n"
[System.IO.File]::WriteAllText((Join-Path $DepDir "lib.vire"), $lib, $utf8)
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($lib)))).Replace("-", "").ToLowerInvariant()
[System.IO.File]::WriteAllText((Join-Path $Work "deps.lock"), "$Pkg $hash`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $Work "app.vire"), $app, $utf8)
Copy-Item (Join-Path $Root "compiler.vire") (Join-Path $Work "compiler.vire") -Force
foreach ($name in @("stage1.vc", "stage2.vc", "cc.vc", "stage1.bin", "stage2.bin")) {
    $path = Join-Path $Work $name
    if (Test-Path -LiteralPath $path) { Remove-Item -Force -LiteralPath $path }
}

function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & dotnet exec $VireDll @Args
    if ($LASTEXITCODE -ne 0) { throw "vire failed: $Args" }
}

Write-Output "interpreter compiles the deps program to stage1.vc"
Invoke-Vire compiler.vire data/app.vire data/stage1.vc
Write-Output "interpreter compiles compiler.vire so a compiled program can compile again"
Invoke-Vire compiler.vire data/compiler.vire data/cc.vc
Write-Output "compiled compiler compiles the same deps program to stage2.vc"
# Paths are relative to data/ (stage sandbox root). need joins to deps/greet/lib.vire.
Invoke-Vire run data/cc.vc app.vire stage2.vc

function Get-PayloadSha([string]$Path) {
    $out = Invoke-Vire payload-sha256 $Path
    if ($out -is [array]) { return $out[-1].ToString().Trim() }
    return $out.ToString().Trim()
}
$hash1 = Get-PayloadSha "data/stage1.vc"
$hash2 = Get-PayloadSha "data/stage2.vc"
Write-Output "stage1 $hash1"
Write-Output "stage2 $hash2"
if ($hash1 -ne $hash2) {
    Write-Error "deps-selfhost hashes differ"
    exit 1
}
Invoke-Vire payload-write data/stage1.vc data/stage1.bin
Invoke-Vire payload-write data/stage2.vc data/stage2.bin
$p1 = [System.IO.File]::ReadAllBytes((Join-Path $Work "stage1.bin"))
$p2 = [System.IO.File]::ReadAllBytes((Join-Path $Work "stage2.bin"))
if (Compare-Object $p1 $p2) {
    Write-Error "stage-1 payload bytes != stage-2 payload bytes"
    exit 1
}

$printed = Invoke-Vire run data/stage2.vc
$line = if ($printed -is [array]) { ($printed | Select-Object -Last 1).ToString().Trim() } else { $printed.ToString().Trim() }
Write-Output "ran $line"
if ($line -ne "deps-selfhost-ok") {
    Write-Error "compiled program did not print deps-selfhost-ok"
    exit 1
}
Write-Output "deps-selfhost ok"
