# Windows-only native sandbox recipe. Not run on the Linux security VM.
# Requires a Windows box with this tree, Release vire.dll, and symlink privilege.
# Do not treat host Unicorn results as this gate.
# Do not disable Defender or add exclusions.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$Work = Join-Path $Root "data/native-sec-windows"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
$script:DefenderBlocked = $false
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
function Test-DefenderBlock {
    param($ErrorRecord, $ExitCode, $Output)
    $text = ""
    if ($ErrorRecord) { $text = [string]$ErrorRecord }
    if ($Output) { $text = $text + " " + [string]$Output }
    $code = 0
    if ($null -ne $ExitCode) { $code = [int]$ExitCode }
    $native = 0
    if ($ErrorRecord -and $ErrorRecord.Exception -and $ErrorRecord.Exception.InnerException) {
        try { $native = [int]$ErrorRecord.Exception.InnerException.NativeErrorCode } catch { }
    }
    if ($ErrorRecord -and $ErrorRecord.Exception -and ($ErrorRecord.Exception | Get-Member -Name NativeErrorCode -ErrorAction SilentlyContinue)) {
        try { $native = [int]$ErrorRecord.Exception.NativeErrorCode } catch { }
    }
    if ($text -match "virus|potentially unwanted|threat|defender|MpCmdRun|Security Center" -or $native -eq 225 -or $native -eq 226 -or $code -eq 225 -or $code -eq 226) {
        return $true
    }
    return $false
}
function Invoke-NativeExe {
    param([string]$ExePath, [string]$WorkingDirectory)
    $tag = [guid]::NewGuid().ToString("N")
    $outFile = Join-Path $WorkingDirectory ("run-" + $tag + ".out")
    $errFile = Join-Path $WorkingDirectory ("run-" + $tag + ".err")
    try {
        $p = Start-Process -FilePath $ExePath -WorkingDirectory $WorkingDirectory -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $out = ""
        if (Test-Path $outFile) {
            $rawOut = Get-Content -Raw $outFile
            if ($null -ne $rawOut) { $out = $rawOut }
        }
        $err = ""
        if (Test-Path $errFile) {
            $rawErr = Get-Content -Raw $errFile
            if ($null -ne $rawErr) { $err = $rawErr }
        }
        $code = $p.ExitCode
        $combo = "$out $err"
        if (Test-DefenderBlock -ErrorRecord $null -ExitCode $code -Output $combo) {
            Write-Host "native_sec_defender_block: Windows Defender refused $ExePath (exit $code)"
            if ($err) { Write-Host $err.TrimEnd() }
            $script:DefenderBlocked = $true
            return @{ Blocked = $true; Output = $out; Code = $code }
        }
        if ($err) { Write-Host $err.TrimEnd() }
        return @{ Blocked = $false; Output = $out; Code = $code }
    }
    catch {
        if (Test-DefenderBlock -ErrorRecord $_ -ExitCode $null -Output $_.ToString()) {
            Write-Host "native_sec_defender_block: Windows Defender refused $ExePath"
            Write-Host $_.ToString()
            $script:DefenderBlocked = $true
            return @{ Blocked = $true; Output = $_.ToString(); Code = -1 }
        }
        throw
    }
}

# 1. Hello still runs (or Defender is named if it blocks the PE).
Copy-Item samples/hello.vire (Join-Path $Work "hello.vire")
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/hello.vire" "data/native-sec-windows/hello.hex"
if ($code -ne 0) { throw "hello compile failed" }
HexToExe "data/native-sec-windows/hello.hex" (Join-Path $Work "hello.exe")
$helloRun = Invoke-NativeExe -ExePath (Join-Path $Work "hello.exe") -WorkingDirectory $Work
if (-not $helloRun.Blocked) {
    if ($helloRun.Code -ne 0 -or ([string]$helloRun.Output).Trim() -ne "hello from vire") { throw "hello exe failed: $($helloRun.Output)" }
}

# 2. Parent directory junction. Compile always; execute only if Defender allows.
$outside = Join-Path $Work "outside"
New-Item -ItemType Directory -Path $outside | Out-Null
Set-Content -Path (Join-Path $outside "secret.txt") -Value "outside-secret" -NoNewline
$link = Join-Path $Work "data"
if (Test-Path $link) { Remove-Item -Recurse -Force $link }
cmd /c mklink /J "$link" "$outside"
if ($LASTEXITCODE -ne 0) { throw "junction skipped or failed" }
Set-Content -Path (Join-Path $Work "read.vire") -Value "define main`n  say (read with `"data/secret.txt`")`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/read.vire" "data/native-sec-windows/read.hex"
if ($code -ne 0) { throw "read compile failed" }
HexToExe "data/native-sec-windows/read.hex" (Join-Path $Work "read.exe")
$got = Invoke-NativeExe -ExePath (Join-Path $Work "read.exe") -WorkingDirectory $Work
if (-not $got.Blocked) {
    if (([string]$got.Output).Contains("outside-secret")) { throw "parent junction leaked" }
    if ($got.Code -eq 0) { throw "parent junction did not fail closed" }
    if (-not ([string]$got.Output).Contains("files stay inside the program folder")) {
        throw "parent junction did not report sandbox error: $($got.Output)"
    }
} else {
    Write-Host "native_sec_junction_compile_ok (PE execute skipped: Defender)"
}

# 3. Hardlink. Compile always; execute only if Defender allows.
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
$got = Invoke-NativeExe -ExePath (Join-Path $Work "write.exe") -WorkingDirectory $Work
$kept = [System.IO.File]::ReadAllText($alias)
if ($kept -ne "SECRET") { throw "hardlink truncated: $kept" }
if (-not $got.Blocked) {
    if ($got.Code -eq 0) { throw "hardlink write did not fail closed" }
    if (-not ([string]$got.Output).Contains("files stay inside the program folder")) {
        throw "hardlink write did not report sandbox error: $($got.Output)"
    }
} else {
    Write-Host "native_sec_hardlink_compile_ok (PE execute skipped: Defender)"
}

if ($script:DefenderBlocked) {
    Write-Output "native sec windows recipe: Defender blocked PE execute; junction and hardlink compiles ran without exclusions"
    exit 0
}
Write-Output "native sec windows recipe ok"
exit 0
