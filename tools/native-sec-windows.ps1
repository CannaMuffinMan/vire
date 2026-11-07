# Local Windows native sandbox handoff. Cloud Linux Unicorn is not this gate.
# See tools/NATIVE-SEC-WINDOWS-HANDOFF.md for pin, timeouts, expected refusals.
# Does not change PATH, registry, firewall, credentials, or symlink policy.
param(
    [switch]$KeepOnFail,
    [switch]$RunSelfHost
)
$ErrorActionPreference = "Stop"
$WallSeconds = 180
$SelfHostSeconds = 600
$started = Get-Date
function Guard-Time([int]$limit) {
    $elapsed = ((Get-Date) - $started).TotalSeconds
    if ($elapsed -gt $limit) { throw "timeout ${limit}s elapsed=$elapsed" }
}

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$RepoArtifacts = Join-Path $Root "data/native-sec-windows/artifacts"
New-Item -ItemType Directory -Force -Path $RepoArtifacts | Out-Null

$ref = "unknown"
try { $ref = (git -C $Root rev-parse HEAD).Trim() } catch { }
Set-Content -Path (Join-Path $RepoArtifacts "ref.txt") -Value $ref

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll ; build Release first" }

$stamp = Get-Date -Format "yyyyMMddHHmmss"
$Fixture = Join-Path $env:TEMP ("vire-native-sec-" + $stamp)
New-Item -ItemType Directory -Path $Fixture | Out-Null
$Art = Join-Path $Fixture "artifacts"
New-Item -ItemType Directory -Path $Art | Out-Null
Set-Content -Path (Join-Path $Art "ref.txt") -Value $ref
$failed = $false
$blocked = $false
$results = New-Object System.Collections.Generic.List[string]

function Note([string]$line) {
    $results.Add($line)
    Write-Output $line
}

function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    Guard-Time $WallSeconds
    $out = & dotnet exec $VireDll @Args
    $code = $LASTEXITCODE
    if ($null -ne $out) { $out | Write-Host }
    if ($null -eq $code) { return 0 }
    return [int]$code
}

function HexToExe($hexRel, $exePath) {
    $hex = [System.IO.File]::ReadAllText((Join-Path $Root $hexRel)).Trim()
    if (($hex.Length % 2) -ne 0) { throw "bad hex $hexRel" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($exePath, $bytes)
}

function Run-Exe([string]$exe, [string]$cwd, [string]$logName) {
    Guard-Time $WallSeconds
    $log = Join-Path $Art $logName
    $p = Start-Process -FilePath $exe -WorkingDirectory $cwd -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput ($log + ".stdout") -RedirectStandardError ($log + ".stderr")
    $stdout = ""
    $stderr = ""
    if (Test-Path ($log + ".stdout")) { $stdout = [IO.File]::ReadAllText($log + ".stdout") }
    if (Test-Path ($log + ".stderr")) { $stderr = [IO.File]::ReadAllText($log + ".stderr") }
    $combined = $stdout + $stderr
    [PSCustomObject]@{ Code = [int]$p.ExitCode; Text = $combined }
}

$WorkHex = Join-Path $Root "data/native-sec-windows"
New-Item -ItemType Directory -Force -Path (Join-Path $WorkHex "data") | Out-Null

try {
    Copy-Item (Join-Path $Root "samples/hello.vire") (Join-Path $WorkHex "hello.vire") -Force
    $code = Invoke-Vire compile-native.vire "data/native-sec-windows/hello.vire" "data/native-sec-windows/hello.hex"
    if ($code -ne 0) { throw "hello compile failed" }
    HexToExe "data/native-sec-windows/hello.hex" (Join-Path $Fixture "hello.exe")
    $got = Run-Exe (Join-Path $Fixture "hello.exe") $Fixture "hello"
    if ($got.Code -ne 0 -or $got.Text.Trim() -ne "hello from vire") {
        throw "hello exe failed: code=$($got.Code) text=$($got.Text)"
    }
    Note "PASS hello"

    $outside = Join-Path $Fixture "outside"
    New-Item -ItemType Directory -Path $outside | Out-Null
    Set-Content -Path (Join-Path $outside "secret.txt") -Value "outside-secret" -NoNewline
    $link = Join-Path $Fixture "data"
    cmd /c mklink /J "$link" "$outside" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Note "BLOCKED mklink /J (need Developer Mode or SeCreateSymbolicLink)"
        $blocked = $true
    } else {
        Set-Content -Path (Join-Path $WorkHex "read.vire") -Value "define main`n  say (read with `"data/secret.txt`")`nend`n"
        $code = Invoke-Vire compile-native.vire "data/native-sec-windows/read.vire" "data/native-sec-windows/read.hex"
        if ($code -ne 0) { throw "read compile failed" }
        HexToExe "data/native-sec-windows/read.hex" (Join-Path $Fixture "read.exe")
        $got = Run-Exe (Join-Path $Fixture "read.exe") $Fixture "junction"
        $keptOutside = [IO.File]::ReadAllText((Join-Path $outside "secret.txt"))
        if ($got.Text.Contains("outside-secret")) { throw "parent junction leaked" }
        if ($keptOutside -ne "outside-secret") { throw "outside secret mutated: $keptOutside" }
        if ($got.Code -eq 0) { throw "parent junction did not fail closed" }
        if (-not $got.Text.Contains("files stay inside the program folder")) {
            throw "parent junction message missing: $($got.Text)"
        }
        Note "PASS parent junction"
        cmd /c rmdir "$link" | Out-Null
    }

    if (-not $blocked) {
        New-Item -ItemType Directory -Path (Join-Path $Fixture "data") | Out-Null
        $note = Join-Path $Fixture "data\note.txt"
        $alias = Join-Path $Fixture "data\alias.txt"
        Set-Content -Path $note -Value "SECRET" -NoNewline
        cmd /c mklink /H "$alias" "$note" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Note "BLOCKED mklink /H"
            $blocked = $true
        } else {
            Set-Content -Path (Join-Path $WorkHex "write.vire") -Value "define main`n  write with `"data/note.txt`", `"hacked`"`nend`n"
            $code = Invoke-Vire compile-native.vire "data/native-sec-windows/write.vire" "data/native-sec-windows/write.hex"
            if ($code -ne 0) { throw "write compile failed" }
            HexToExe "data/native-sec-windows/write.hex" (Join-Path $Fixture "write.exe")
            $got = Run-Exe (Join-Path $Fixture "write.exe") $Fixture "hardlink"
            $keptAlias = [IO.File]::ReadAllText($alias)
            $keptNote = [IO.File]::ReadAllText($note)
            if ($keptAlias -ne "SECRET" -or $keptNote -ne "SECRET") { throw "hardlink truncated alias=$keptAlias note=$keptNote" }
            if ($got.Code -eq 0) { throw "hardlink write did not fail closed" }
            if (-not $got.Text.Contains("files stay inside the program folder")) {
                throw "hardlink message missing: $($got.Text)"
            }
            Note "PASS hardlink nlink"
        }
    }

    Set-Content -Path (Join-Path $Fixture "outside.txt") -Value "outside-keep" -NoNewline
    Set-Content -Path (Join-Path $WorkHex "dotdot.vire") -Value "define main`n  write with `"data/../outside.txt`", `"hacked`"`nend`n"
    $code = Invoke-Vire compile-native.vire "data/native-sec-windows/dotdot.vire" "data/native-sec-windows/dotdot.hex"
    if ($code -ne 0) { throw "dotdot compile failed" }
    HexToExe "data/native-sec-windows/dotdot.hex" (Join-Path $Fixture "dotdot.exe")
    $got = Run-Exe (Join-Path $Fixture "dotdot.exe") $Fixture "dotdot"
    $keptDot = [IO.File]::ReadAllText((Join-Path $Fixture "outside.txt"))
    if ($keptDot -ne "outside-keep") { throw "dotdot mutated outside.txt: $keptDot" }
    if ($got.Code -eq 0) { throw "dotdot did not fail closed" }
    if (-not $got.Text.Contains("files stay inside the program folder")) {
        throw "dotdot message missing: $($got.Text)"
    }
    Note "PASS dotdot"

    Set-Content -Path (Join-Path $WorkHex "deep.vire") -Value "define boom with n`n  if n > 0`n    boom with (n - 1)`n  end`nend`ndefine main`n  boom with 65`n  say `"survived`"`nend`n"
    $code = Invoke-Vire compile-native.vire "data/native-sec-windows/deep.vire" "data/native-sec-windows/deep.hex"
    if ($code -ne 0) { throw "deep compile failed" }
    HexToExe "data/native-sec-windows/deep.hex" (Join-Path $Fixture "deep.exe")
    $got = Run-Exe (Join-Path $Fixture "deep.exe") $Fixture "deep"
    if ($got.Text.Contains("survived")) { throw "deep recursion survived" }
    if (-not $got.Text.Contains("definitions called too deeply")) {
        throw "deep message missing: $($got.Text)"
    }
    if ($got.Code -eq 0) { throw "deep did not fail closed" }
    Note "PASS frame depth 65"

    if ($RunSelfHost) {
        Guard-Time $SelfHostSeconds
        Note "SKIP gen1-gen2: native read is data|site only; use files are src/*.vire. hello-stage optional via tools/native-selfhost-proof.ps1 on Windows."
    }
}
catch {
    $failed = $true
    Note ("FAIL " + $_.Exception.Message)
}

$results | Set-Content (Join-Path $Art "results.txt")
Copy-Item -Recurse -Force $Art $RepoArtifacts
Note ("fixture $Fixture")
Note ("ref $ref")

if (-not $failed -and -not $KeepOnFail) {
    try { Remove-Item -Recurse -Force $Fixture } catch { }
}

if ($blocked) { exit 2 }
if ($failed) { exit 1 }
Write-Output "native sec windows recipe ok"
exit 0
