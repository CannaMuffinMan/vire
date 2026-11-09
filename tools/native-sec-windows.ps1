# Windows-only native sandbox recipe. Not run on the Linux security VM.
# Requires a Windows box with this tree, Release vire.dll, and symlink privilege.
# Do not treat host Unicorn results as this gate.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-sec-windows"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path (Join-Path $Work "data") | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
function Invoke-Vire {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [int]$TimeoutSec = 120,
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$VireArgs
    )
    $work = Join-Path $Work ("invoke-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $outFile = Join-Path $work "out.txt"
    $errFile = Join-Path $work "err.txt"
    $inFile = Join-Path $work "in.txt"
    Set-Content -Path $inFile -Value "" -NoNewline
    $argList = @("exec", $VireDll) + $VireArgs
    $p = Start-Process -FilePath "dotnet" -ArgumentList $argList -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill($true) } catch { }
        throw "vire timed out after ${TimeoutSec}s: $($VireArgs -join ' ')"
    }
    $out = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
    $err = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
    if ($out) { $out.TrimEnd() | Write-Host }
    if ($err) { $err.TrimEnd() | Write-Host }
    if ($null -eq $p.ExitCode) { return 0 }
    return [int]$p.ExitCode
}
function HexToExe($hexRel, $exePath) {
    $hex = [System.IO.File]::ReadAllText((Join-Path $Root $hexRel)).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($exePath, $bytes)
}

# 1. Hello still runs.
Copy-Item samples/hello.vire (Join-Path $Work "hello.vire")
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/hello.vire" "data/native-sec-windows/hello.hex"
if ($code -ne 0) { throw "hello compile failed" }
HexToExe "data/native-sec-windows/hello.hex" (Join-Path $Work "hello.exe")
$got = & (Join-Path $Work "hello.exe") | Out-String
if ($LASTEXITCODE -ne 0 -or $got.Trim() -ne "hello from vire") { throw "hello exe failed: $got" }

# 2. Parent directory junction must not leak.
$outside = Join-Path $Work "outside"
New-Item -ItemType Directory -Path $outside | Out-Null
Set-Content -Path (Join-Path $outside "secret.txt") -Value "outside-secret" -NoNewline
$link = Join-Path $Work "data"
cmd /c mklink /J "$link" "$outside"
if ($LASTEXITCODE -ne 0) { throw "junction skipped or failed" }
Set-Content -Path (Join-Path $Work "read.vire") -Value "define main`n  say (read with `"data/secret.txt`")`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/read.vire" "data/native-sec-windows/read.hex"
if ($code -ne 0) { throw "read compile failed" }
HexToExe "data/native-sec-windows/read.hex" (Join-Path $Work "read.exe")
$got = & (Join-Path $Work "read.exe") 2>&1 | Out-String
if ($got.Contains("outside-secret")) { throw "parent junction leaked" }
if ($LASTEXITCODE -eq 0) { throw "parent junction did not fail closed" }

# 3. Hardlink must not be truncated by write.
Remove-Item -Force $link
New-Item -ItemType Directory -Path (Join-Path $Work "data") | Out-Null
$note = Join-Path $Work "data\note.txt"
$alias = Join-Path $Work "data\alias.txt"
Set-Content -Path $note -Value "SECRET" -NoNewline
cmd /c mklink /H "$alias" "$note"
Set-Content -Path (Join-Path $Work "write.vire") -Value "define main`n  write with `"data/note.txt`", `"hacked`"`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/write.vire" "data/native-sec-windows/write.hex"
if ($code -ne 0) { throw "write compile failed" }
HexToExe "data/native-sec-windows/write.hex" (Join-Path $Work "write.exe")
$got = & (Join-Path $Work "write.exe") 2>&1 | Out-String
$kept = [System.IO.File]::ReadAllText($alias)
if ($kept -ne "SECRET") { throw "hardlink truncated: $kept" }
if ($LASTEXITCODE -eq 0) { throw "hardlink write did not fail closed" }

Write-Output "native sec windows recipe ok"
exit 0
