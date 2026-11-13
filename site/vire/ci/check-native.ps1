# Compile every runnable homepage sample to a Windows PE and check stdout.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
Set-Location -LiteralPath $Root
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

$Work = Join-Path $Root "data/site-vire-native"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
Copy-Item (Join-Path $Root "site/vire/examples/*.vire") $Work
$Manifest = Get-Content (Join-Path $Root "site/vire/examples/manifest.txt")
$failed = $false
foreach ($line in $Manifest) {
    $name = $line.Trim()
    if ($name -eq "" -or $name.StartsWith("#")) { continue }
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    Write-Output "native $name"
    $srcRel = "data/site-vire-native/$name"
    $hexRel = "data/site-vire-native/$base.hex"
    $saved = $env:VIRE_BUDGET
    Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    $compile = & dotnet exec $VireDll --compiler compile-native.vire $srcRel $hexRel
    $code = $LASTEXITCODE
    if ($saved) { $env:VIRE_BUDGET = $saved }
    if ($null -ne $compile) { $compile | Write-Host }
    if ($code -ne 0) {
        Write-Output "FAIL compile $name exit=$code"
        $failed = $true
        continue
    }
    $exe = Join-Path $Work ($base + ".exe")
    Convert-HexToExe (Join-Path $Root $hexRel) $exe
    try { Unblock-File -Path $exe } catch { }
    $got = & $exe | Out-String
    $exit = $LASTEXITCODE
    $got = ($got -replace "`r", "").TrimEnd()
    $want = ([IO.File]::ReadAllText((Join-Path $Root "site/vire/examples/$base.out")) -replace "`r", "").TrimEnd()
    if ($got -eq $want -and $exit -eq 0) {
        Write-Output "PASS native $name"
    } else {
        Write-Output "FAIL run $name exit=$exit"
        Write-Output "want:"
        Write-Output $want
        Write-Output "got:"
        Write-Output $got
        $failed = $true
    }
}
if ($failed) { exit 1 }
Write-Output "site-vire native ok"
