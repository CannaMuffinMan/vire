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
        if ($out) { Write-Host $out.TrimEnd() }
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

function Get-VulnTree {
    $sha = "7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867"
    $dir = [string](Join-Path ([IO.Path]::GetTempPath()) ("vire-vuln-" + $sha.Substring(0, 12)))
    if (-not (Test-Path -LiteralPath (Join-Path $dir "compile-native.vire"))) {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        # git writes to the success stream; do not let that become the function output (Copy-Item Destination Object[]).
        & git fetch --depth 1 origin $sha 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "git fetch $sha failed" }
        & git worktree add --detach $dir $sha 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "git worktree add $dir $sha failed" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dir "compile-native.vire"))) { throw "vuln tree missing compile-native.vire" }
    return [string]$dir
}

function Invoke-VireAt {
    param([string]$WorkingDirectory, [string[]]$VireArgs, [int]$TimeoutSec = 180)
    $outFile = Join-Path $Work ("at-" + [guid]::NewGuid().ToString("N") + ".out")
    $errFile = "$outFile.err"
    $inFile = "$outFile.in"
    Set-Content -Path $inFile -Value "" -NoNewline
    $argList = @("exec", $VireDll) + $VireArgs
    $p = Start-Process -FilePath "dotnet" -ArgumentList $argList -WorkingDirectory $WorkingDirectory -NoNewWindow -PassThru -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill($true) } catch { }
        throw "vire timed out in $WorkingDirectory"
    }
    $out = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
    $err = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
    if ($out) { $out.TrimEnd() | Write-Host }
    if ($err) { $err.TrimEnd() | Write-Host }
    if ($p.ExitCode -ne 0) { throw "vire exit $($p.ExitCode) in $WorkingDirectory : $out $err" }
}

function Convert-HexFileToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Get-PeEntryFileOffset([byte[]]$pe) {
    $e = [BitConverter]::ToInt32($pe, 0x3C)
    $n = [BitConverter]::ToInt16($pe, $e + 6)
    $soh = [BitConverter]::ToUInt16($pe, $e + 20)
    $entryRva = [BitConverter]::ToInt32($pe, $e + 24 + 16)
    $sec = $e + 24 + $soh
    for ($i = 0; $i -lt $n; $i++) {
        $off = $sec + $i * 40
        $va = [BitConverter]::ToInt32($pe, $off + 12)
        $vsz = [BitConverter]::ToInt32($pe, $off + 8)
        $rp = [BitConverter]::ToInt32($pe, $off + 20)
        $rs = [BitConverter]::ToInt32($pe, $off + 16)
        $span = [Math]::Max($vsz, $rs)
        if ($entryRva -ge $va -and $entryRva -lt ($va + $span)) {
            return $rp + ($entryRva - $va)
        }
    }
    throw "PE entry RVA $entryRva not in a section"
}

function Get-PeAsciiSection([string]$ExePath, [string]$Ascii) {
    $pe = [IO.File]::ReadAllBytes($ExePath)
    $need = [Text.Encoding]::ASCII.GetBytes($Ascii)
    $at = -1
    $i = 0
    while ($i -le ($pe.Length - $need.Length)) {
        $ok = $true
        $k = 0
        while ($k -lt $need.Length) {
            if ($pe[$i + $k] -ne $need[$k]) { $ok = $false; break }
            $k++
        }
        if ($ok) { $at = $i; break }
        $i++
    }
    if ($at -lt 0) { throw "ascii not in PE: $Ascii" }
    $e = [BitConverter]::ToInt32($pe, 0x3C)
    $n = [BitConverter]::ToInt16($pe, $e + 6)
    $soh = [BitConverter]::ToUInt16($pe, $e + 20)
    $sec = $e + 24 + $soh
    $i = 0
    while ($i -lt $n) {
        $off = $sec + $i * 40
        $name = [Text.Encoding]::ASCII.GetString($pe, $off, 8).Trim([char]0)
        $vsz = [BitConverter]::ToInt32($pe, $off + 8)
        $va = [BitConverter]::ToInt32($pe, $off + 12)
        $rs = [BitConverter]::ToInt32($pe, $off + 16)
        $rp = [BitConverter]::ToInt32($pe, $off + 20)
        $ch = [BitConverter]::ToUInt32($pe, $off + 36)
        if ($at -ge $rp -and $at -lt ($rp + $rs)) {
            $rx = (($ch -band 0x20000000) -ne 0) -and (($ch -band 0x40000000) -ne 0) -and (($ch -band 0x80000000) -eq 0)
            $rw = (($ch -band 0x80000000) -ne 0) -and (($ch -band 0x20000000) -eq 0)
            return @{ Name = $name; FileOff = $at; Chars = $ch; Rx = $rx; Rw = $rw; Va = $va; Vsz = $vsz }
        }
        $i++
    }
    throw "ascii $Ascii at $at not in a section"
}

function Set-CrashEntry([string]$SrcExe, [string]$DstExe) {
    $pe = [IO.File]::ReadAllBytes($SrcExe)
    $at = Get-PeEntryFileOffset $pe
    $i = $at
    $ff = 0
    while ($i -lt ($pe.Length - 6)) {
        if ($pe[$i] -eq 0xFF -and $pe[$i + 1] -eq 0x15) {
            $ff++
            $i += 6
            if ($ff -eq 4) { break }
        } else {
            $i++
        }
    }
    $e8 = 0
    $hit = -1
    while ($i -lt ($pe.Length - 6)) {
        if ($pe[$i] -eq 0xE8) {
            $e8++
            if ($e8 -eq 2) { $hit = $i; break }
            $i += 5
        } else {
            $i++
        }
    }
    if ($hit -lt 0) { throw "call fn_main not found after VEH setup" }
    $patch = [byte[]](0x48, 0x31, 0xC0, 0x48, 0x8B, 0x00)
    [Array]::Copy($patch, 0, $pe, $hit, $patch.Length)
    [IO.File]::WriteAllBytes($DstExe, $pe)
}

$VulnTree = [string](Get-VulnTree)
if (-not (Test-Path -LiteralPath (Join-Path $VulnTree "compile-native.vire"))) {
    throw "VulnTree is not a directory with compile-native.vire: $VulnTree"
}
Write-Host "f456_vuln_tree $VulnTree"

# 4. F4: intern section named; RW mutation vs RX AV. Same cell via let p.
New-Item -ItemType Directory -Force -Path (Join-Path $Work "data\f4") | Out-Null
Set-Content -Path (Join-Path $Work "data\f4\note.txt") -Value "NOTE" -NoNewline
Set-Content -Path (Join-Path $Work "f4.vire") -Value "define main`n  let p be `"data/f4/note.txt`"`n  say (read with p)`n  say (read with p)`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/f4.vire" "data/native-sec-windows/f4.hex"
if ($code -ne 0) { throw "f4 compile failed" }
HexToExe "data/native-sec-windows/f4.hex" (Join-Path $Work "f4.exe")
$vulnData = [string](Join-Path $VulnTree "data")
New-Item -ItemType Directory -Force -Path $vulnData | Out-Null
Copy-Item -LiteralPath ([string](Join-Path $Work "f4.vire")) -Destination ([string](Join-Path $vulnData "native-sec-windows-f4.vire")) -Force
Invoke-VireAt -WorkingDirectory $VulnTree -VireArgs @((Join-Path $VulnTree "compile-native.vire"), "data/native-sec-windows-f4.vire", "data/f4-vuln.hex")
Convert-HexFileToExe (Join-Path $VulnTree "data/f4-vuln.hex") (Join-Path $Work "f4-vuln.exe")

function Count-Note([string]$text) {
    [int]$n = 0
    $t = [string]$text
    $idx = 0
    while ($true) {
        $at = $t.IndexOf("NOTE", $idx)
        if ($at -lt 0) { break }
        $n = $n + 1
        $idx = $at + 4
    }
    return [int]$n
}

$internFix = Get-PeAsciiSection (Join-Path $Work "f4.exe") "data/f4/note.txt"
$internVuln = Get-PeAsciiSection (Join-Path $Work "f4-vuln.exe") "data/f4/note.txt"
Write-Host ("f4_intern_section fixed=" + $internFix.Name + " ch=" + ("{0:X8}" -f $internFix.Chars) + " rx=" + $internFix.Rx + " rw=" + $internFix.Rw)
Write-Host ("f4_intern_section vuln=" + $internVuln.Name + " ch=" + ("{0:X8}" -f $internVuln.Chars) + " rx=" + $internVuln.Rx + " rw=" + $internVuln.Rw)
if ($internFix.Rx -and $internVuln.Rx) {
    Write-Host "f4_claim RX .text"
} else {
    Write-Host "f4_claim not RX (Copilot .text claim dropped); intern in $($internFix.Name)"
}

if ($script:DefenderBlocked) { throw "Defender blocked before F4/F5/F6 OS properties" }

$f4fix = Invoke-NativeExe -ExePath (Join-Path $Work "f4.exe") -WorkingDirectory $Work
$f4vuln = Invoke-NativeExe -ExePath (Join-Path $Work "f4-vuln.exe") -WorkingDirectory $Work
if ($f4fix.Blocked -or $f4vuln.Blocked) { throw "Defender blocked F4 PE execute" }
$fn = Count-Note $f4fix.Output
$vn = Count-Note $f4vuln.Output
Write-Host ("f4_double_read fixed NOTE x" + $fn + " code=" + $f4fix.Code)
Write-Host ("f4_double_read vuln NOTE x" + $vn + " code=" + $f4vuln.Code)
if ($internFix.Rx -or $internVuln.Rx) {
    if ($f4vuln.Code -eq 0) { throw "f4 RX claim requires vuln store AV, got exit 0" }
    if ($fn -lt 2 -or $f4fix.Code -ne 0) { throw "f4 RX pass-after: fixed PE must read NOTE twice" }
} else {
    if ($f4fix.Code -ne 0 -or $fn -lt 2) { throw "f4_double_read fixed PE must print NOTE twice: $($f4fix.Output)" }
    if ($vn -ge 2) { throw "f4 fail-before missing: vuln PE still printed NOTE twice (no intern mutation)" }
    Write-Host "f4_double_read fail-before mutation (vuln NOTE count $vn) pass-after NOTE x$fn"
}

# 5. F5: vuln MUST hit KEEP>=1 (bounded), then fixed victim==0. 0/0 fails.
# 7c7c8ea interned path literals live in RX .text; walk NULs them and AVs (same RIP as F4).
# Heap-concatenated path so CREATE_ALWAYS fail-before can actually run.
Set-Content -Path (Join-Path $Work "f5.vire") -Value "define main`n  write with `"data/f5-slot.txt`", `"HACKED`"`nend`n"
Set-Content -Path (Join-Path $Work "f5-vuln-src.vire") -Value "define main`n  let p be (`"data/`" + `"f5-slot.txt`")`n  write with p, `"HACKED`"`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/f5.vire" "data/native-sec-windows/f5.hex"
if ($code -ne 0) { throw "f5 compile failed" }
HexToExe "data/native-sec-windows/f5.hex" (Join-Path $Work "f5.exe")
Copy-Item -LiteralPath ([string](Join-Path $Work "f5-vuln-src.vire")) -Destination ([string](Join-Path $vulnData "native-sec-windows-f5.vire")) -Force
Invoke-VireAt -WorkingDirectory $VulnTree -VireArgs @((Join-Path $VulnTree "compile-native.vire"), "data/native-sec-windows-f5.vire", "data/f5-vuln.hex")
Convert-HexFileToExe (Join-Path $VulnTree "data/f5-vuln.hex") (Join-Path $Work "f5-vuln.exe")

$racerPath = Join-Path $Work "f5-racer.ps1"
Set-Content -Path $racerPath -Value @'
param($Slot, $Keep)
while ($true) {
    try {
        if (Test-Path -LiteralPath $Slot) { Remove-Item -LiteralPath $Slot -Force -ErrorAction SilentlyContinue }
        cmd /c mklink /H "$Slot" "$Keep" | Out-Null
    } catch { }
}
'@

function Start-F5Racer([string]$Slot, [string]$Keep) {
    return Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-File", $racerPath, $Slot, $Keep) -PassThru -WindowStyle Hidden
}

function Reset-F5Slot([string]$Slot) {
    try {
        if (Test-Path -LiteralPath $Slot) {
            Remove-Item -LiteralPath $Slot -Force -ErrorAction Ignore
        }
    } catch { }
}

function Invoke-F5UntilHit([string]$WriteExe, [int]$TimeoutSec) {
    $keep = Join-Path $Work "data\f5-keep.txt"
    $slot = Join-Path $Work "data\f5-slot.txt"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    [int]$rounds = 0
    $rp = $null
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $Work "data") | Out-Null
        Set-Content -Path $keep -Value "KEEP" -NoNewline | Out-Null
        Reset-F5Slot $slot
        $rp = Start-F5Racer $slot $keep
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            Set-Content -Path $keep -Value "KEEP" -NoNewline | Out-Null
            $run = Invoke-NativeExe -ExePath $WriteExe -WorkingDirectory $Work
            $rounds = $rounds + 1
            if ($run.Blocked) { throw "Defender blocked F5 write PE" }
            $kept = [IO.File]::ReadAllText($keep)
            if (($rounds % 25) -eq 0) { Write-Host ("f5_round " + $rounds + " KEEP=" + $kept + " write_code=" + $run.Code) }
            if ($kept -eq "HACKED" -or $kept.Length -eq 0) {
                Write-Host ("f5_two_process_race vuln victim_hits=1 rounds=" + $rounds + " sec=" + $sw.Elapsed.TotalSeconds.ToString("0.000"))
                return [int]$rounds
            }
        }
    } finally {
        if ($rp) { try { $rp.Kill() | Out-Null } catch { }; try { [void]$rp.WaitForExit(2000) } catch { } }
    }
    throw "f5 fail-before missing: vuln PE did not truncate KEEP in ${TimeoutSec}s ($rounds rounds). 0/0 is a failed gate."
}

function Invoke-F5FixedZero([string]$WriteExe, [int]$TimeoutSec) {
    $keep = Join-Path $Work "data\f5-keep.txt"
    $slot = Join-Path $Work "data\f5-slot.txt"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    [int]$rounds = 0
    [int]$hits = 0
    $rp = $null
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $Work "data") | Out-Null
        Set-Content -Path $keep -Value "KEEP" -NoNewline | Out-Null
        Reset-F5Slot $slot
        $rp = Start-F5Racer $slot $keep
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            Set-Content -Path $keep -Value "KEEP" -NoNewline | Out-Null
            $run = Invoke-NativeExe -ExePath $WriteExe -WorkingDirectory $Work
            $rounds = $rounds + 1
            if ($run.Blocked) { throw "Defender blocked F5 fixed PE" }
            $kept = [IO.File]::ReadAllText($keep)
            if ($kept -eq "HACKED" -or $kept.Length -eq 0) { $hits = $hits + 1 }
        }
    } finally {
        if ($rp) { try { $rp.Kill() | Out-Null } catch { }; try { [void]$rp.WaitForExit(2000) } catch { } }
    }
    Write-Host ("f5_two_process_race fixed victim_hits=" + $hits + " rounds=" + $rounds)
    return [int]$hits
}

$f5vulnRounds = Invoke-F5UntilHit -WriteExe (Join-Path $Work "f5-vuln.exe") -TimeoutSec 90
if ($f5vulnRounds -isnot [int]) { throw "f5 vuln rounds is not int: $($f5vulnRounds.GetType().FullName) $f5vulnRounds" }
$f5fixHits = Invoke-F5FixedZero -WriteExe (Join-Path $Work "f5.exe") -TimeoutSec 20
if ($f5fixHits -isnot [int]) { throw "f5 fixed hits is not int: $($f5fixHits.GetType().FullName) $f5fixHits" }
if ($f5fixHits -ne 0) { throw "f5 pass-after failed: fixed PE truncated KEEP $f5fixHits times" }
Write-Host "f5 reopen-after-nlink closed by SetEndOfFile; walk-then-open identity is f_walk"

# 6. F6: hardlink crash-rip.txt to KEEP under data/. Vuln must smash KEEP. Fixed KEEP + crash rip=.
Copy-Item -LiteralPath ([string](Join-Path $Work "hello.vire")) -Destination ([string](Join-Path $vulnData "native-sec-windows-hello.vire")) -Force
Invoke-VireAt -WorkingDirectory $VulnTree -VireArgs @((Join-Path $VulnTree "compile-native.vire"), "data/native-sec-windows-hello.vire", "data/hello-vuln.hex") -TimeoutSec 180
Convert-HexFileToExe (Join-Path $VulnTree "data/hello-vuln.hex") (Join-Path $Work "hello-vuln.exe")

function Invoke-F6Crash([string]$HelloExe, [string]$Tag) {
    $crashDir = Join-Path $Work ("crash-" + $Tag)
    if (Test-Path $crashDir) { Remove-Item -Recurse -Force $crashDir }
    New-Item -ItemType Directory -Force -Path $crashDir | Out-Null
    $crashExe = Join-Path $crashDir "crash.exe"
    Set-CrashEntry $HelloExe $crashExe
    $keep = Join-Path $crashDir "keep.txt"
    $rip = Join-Path $crashDir "crash-rip.txt"
    Set-Content -Path $keep -Value "KEEP" -NoNewline
    cmd /c mklink /H "$rip" "$keep"
    if ($LASTEXITCODE -ne 0) { throw "f6 mklink /H crash-rip.txt keep.txt failed" }
    $run = Invoke-NativeExe -ExePath $crashExe -WorkingDirectory $crashDir
    $kept = [IO.File]::ReadAllText($keep)
    $ripText = if (Test-Path -LiteralPath $rip) { [IO.File]::ReadAllText($rip) } else { "" }
    Write-Host ("f6_crash_pe " + $Tag + " code=" + $run.Code + " KEEP=" + $kept + " rip=" + ($ripText -replace '\s+', ' ') + " stdout=" + (([string]$run.Output) -replace '\s+', ' '))
    return @{ Run = $run; Keep = $kept; RipText = $ripText }
}

$f6vuln = Invoke-F6Crash -HelloExe (Join-Path $Work "hello-vuln.exe") -Tag "vuln"
if ($f6vuln.Run.Blocked) { throw "Defender blocked F6 vuln crash PE" }
$vulnSmashed = ($f6vuln.Keep -ne "KEEP") -or ($f6vuln.RipText -ne "KEEP")
if (-not $vulnSmashed) { throw "f6 fail-before missing: vuln PE left KEEP and crash-rip.txt as KEEP" }
Write-Host "f6_crash_pe vuln smashed KEEP/rip (fail-before)"

$f6fix = Invoke-F6Crash -HelloExe (Join-Path $Work "hello.exe") -Tag "fixed"
if ($f6fix.Run.Blocked) { throw "Defender blocked F6 fixed crash PE" }
if ($f6fix.Keep -ne "KEEP") { throw "f6 pass-after failed: fixed PE modified KEEP=$($f6fix.Keep)" }
if ($f6fix.RipText -ne "KEEP") { throw "f6 pass-after failed: fixed PE changed crash-rip.txt hardlink" }
if (-not ([string]$f6fix.Run.Output).Contains("crash rip=")) { throw "f6 pass-after missing crash rip= stdout: $($f6fix.Run.Output)" }
Write-Host "f6_crash_pe fixed KEEP intact and stdout crash rip="

# walk-then-open TOCTOU: swap data for a junction to outside between GFA and CreateFileA.
Set-Content -Path (Join-Path $Work "walk.vire") -Value "define main`n  write with `"data/note.txt`", `"hacked`"`nend`n"
Set-Content -Path (Join-Path $Work "walk-vuln-src.vire") -Value "define main`n  let p be (`"data/`" + `"note.txt`")`n  write with p, `"hacked`"`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/walk.vire" "data/native-sec-windows/walk.hex"
if ($code -ne 0) { throw "walk compile failed" }
HexToExe "data/native-sec-windows/walk.hex" (Join-Path $Work "walk.exe")
Copy-Item -LiteralPath ([string](Join-Path $Work "walk-vuln-src.vire")) -Destination ([string](Join-Path $vulnData "native-sec-windows-walk.vire")) -Force
Invoke-VireAt -WorkingDirectory $VulnTree -VireArgs @((Join-Path $VulnTree "compile-native.vire"), "data/native-sec-windows-walk.vire", "data/walk-vuln.hex")
Convert-HexFileToExe (Join-Path $VulnTree "data/walk-vuln.hex") (Join-Path $Work "walk-vuln.exe")

$walkRacer = Join-Path $Work "walk-racer.ps1"
Set-Content -Path $walkRacer -Value @'
param($Work)
$data = Join-Path $Work "data"
$real = Join-Path $Work "data.real"
$outside = Join-Path $Work "outside"
while ($true) {
    try {
        if ((Test-Path -LiteralPath $data) -and -not (Test-Path -LiteralPath $real)) {
            Rename-Item -LiteralPath $data -NewName "data.real" -ErrorAction SilentlyContinue
            cmd /c mklink /J "$data" "$outside" | Out-Null
        }
    } catch { }
}
'@

function Restore-WalkTree {
    $data = Join-Path $Work "data"
    $real = Join-Path $Work "data.real"
    $outside = Join-Path $Work "outside"
    if (Test-Path -LiteralPath $data) {
        $item = Get-Item -LiteralPath $data -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c rmdir "$data" | Out-Null
        } else {
            Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $real) {
        Rename-Item -LiteralPath $real -NewName "data" -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $Work "data") | Out-Null
    New-Item -ItemType Directory -Force -Path $outside | Out-Null
    Set-Content -Path (Join-Path $Work "data\note.txt") -Value "SECRET-KEEP-ME-LONG" -NoNewline
    Set-Content -Path (Join-Path $outside "note.txt") -Value "SECRET-KEEP-ME-LONG" -NoNewline
}

function Invoke-WalkUntilHit([string]$WriteExe, [int]$TimeoutSec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    [int]$rounds = 0
    $rp = $null
    try {
        Restore-WalkTree
        $rp = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-File", $walkRacer, $Work) -PassThru -WindowStyle Hidden
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            $run = Invoke-NativeExe -ExePath $WriteExe -WorkingDirectory $Work
            $rounds = $rounds + 1
            if ($run.Blocked) { throw "Defender blocked walk-then-open write PE" }
            $outsideText = [IO.File]::ReadAllText((Join-Path $Work "outside\note.txt"))
            if (($rounds % 25) -eq 0) { Write-Host ("f_walk_round " + $rounds + " outside=" + $outsideText + " write_code=" + $run.Code) }
            if ($outsideText -eq "hacked") {
                Write-Host ("f_walk_then_open vuln outside_hits=1 rounds=" + $rounds + " sec=" + $sw.Elapsed.TotalSeconds.ToString("0.000"))
                return [int]$rounds
            }
        }
    } finally {
        if ($rp) { try { $rp.Kill() | Out-Null } catch { }; try { [void]$rp.WaitForExit(2000) } catch { } }
        Restore-WalkTree
    }
    throw "f_walk fail-before missing: vuln PE did not write outside in ${TimeoutSec}s ($rounds rounds). 0/0 is a failed gate."
}

function Invoke-WalkFixedZero([string]$WriteExe, [int]$TimeoutSec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    [int]$rounds = 0
    [int]$hits = 0
    $rp = $null
    try {
        Restore-WalkTree
        $rp = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-File", $walkRacer, $Work) -PassThru -WindowStyle Hidden
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            $run = Invoke-NativeExe -ExePath $WriteExe -WorkingDirectory $Work
            $rounds = $rounds + 1
            if ($run.Blocked) { throw "Defender blocked walk-then-open fixed PE" }
            $outsideText = [IO.File]::ReadAllText((Join-Path $Work "outside\note.txt"))
            if ($outsideText -eq "hacked") { $hits = $hits + 1 }
        }
    } finally {
        if ($rp) { try { $rp.Kill() | Out-Null } catch { }; try { [void]$rp.WaitForExit(2000) } catch { } }
        Restore-WalkTree
    }
    Write-Host ("f_walk_then_open fixed outside_hits=" + $hits + " rounds=" + $rounds)
    return [int]$hits
}

$walkVulnRounds = Invoke-WalkUntilHit -WriteExe (Join-Path $Work "walk-vuln.exe") -TimeoutSec 90
if ($walkVulnRounds -isnot [int]) { throw "f_walk vuln rounds is not int: $($walkVulnRounds.GetType().FullName) $walkVulnRounds" }
$walkFixHits = Invoke-WalkFixedZero -WriteExe (Join-Path $Work "walk.exe") -TimeoutSec 20
if ($walkFixHits -isnot [int]) { throw "f_walk fixed hits is not int: $($walkFixHits.GetType().FullName) $walkFixHits" }
if ($walkFixHits -ne 0) { throw "f_walk pass-after failed: fixed PE wrote outside $walkFixHits times" }
Write-Host "f_walk_then_open GetFinalPathNameByHandle identity closed"

if ($script:DefenderBlocked) {
    Write-Output "native sec windows recipe: Defender blocked PE execute; junction and hardlink compiles ran without exclusions"
    exit 0
}
Write-Output "native sec windows recipe ok"
exit 0
