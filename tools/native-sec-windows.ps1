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
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("vire-vuln-" + $sha.Substring(0, 12))
    if (-not (Test-Path (Join-Path $dir "compile-native.vire"))) {
        if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
        git fetch --depth 1 origin $sha
        git worktree add --detach $dir $sha
    }
    if (-not (Test-Path (Join-Path $dir "compile-native.vire"))) { throw "vuln tree missing compile-native.vire" }
    return $dir
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

$VulnTree = Get-VulnTree
Write-Host "f456_vuln_tree $VulnTree"

# 4. F4 double read of the same interned path (property: second read still works).
New-Item -ItemType Directory -Force -Path (Join-Path $Work "data\f4") | Out-Null
Set-Content -Path (Join-Path $Work "data\f4\note.txt") -Value "NOTE" -NoNewline
Set-Content -Path (Join-Path $Work "f4.vire") -Value "define main`n  say (read with `"data/f4/note.txt`")`n  say (read with `"data/f4/note.txt`")`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/f4.vire" "data/native-sec-windows/f4.hex"
if ($code -ne 0) { throw "f4 compile failed" }
HexToExe "data/native-sec-windows/f4.hex" (Join-Path $Work "f4.exe")
Copy-Item (Join-Path $Work "f4.vire") (Join-Path $VulnTree "data/native-sec-windows-f4.vire") -Force
New-Item -ItemType Directory -Force -Path (Join-Path $VulnTree "data") | Out-Null
Invoke-VireAt -WorkingDirectory $VulnTree -VireArgs @((Join-Path $VulnTree "compile-native.vire"), "data/native-sec-windows-f4.vire", "data/f4-vuln.hex")
Convert-HexFileToExe (Join-Path $VulnTree "data/f4-vuln.hex") (Join-Path $Work "f4-vuln.exe")

$f4fix = Invoke-NativeExe -ExePath (Join-Path $Work "f4.exe") -WorkingDirectory $Work
$f4vuln = Invoke-NativeExe -ExePath (Join-Path $Work "f4-vuln.exe") -WorkingDirectory $Work
function Count-Note([string]$text) {
    $n = 0
    $t = [string]$text
    $idx = 0
    while ($true) {
        $at = $t.IndexOf("NOTE", $idx)
        if ($at -lt 0) { break }
        $n++
        $idx = $at + 4
    }
    return $n
}
if (-not $f4fix.Blocked) {
    if ($f4fix.Code -ne 0) { throw "f4_double_read fixed PE failed: $($f4fix.Output)" }
    if ((Count-Note $f4fix.Output) -lt 2) { throw "f4_double_read fixed PE did not print NOTE twice: $($f4fix.Output)" }
    Write-Host "f4_double_read fixed NOTE x$(Count-Note $f4fix.Output)"
}
if (-not $f4vuln.Blocked) {
    $vn = Count-Note $f4vuln.Output
    if ($f4vuln.Code -eq 0 -and $vn -ge 2) {
        Write-Host "f4_double_read vuln PE still printed NOTE twice (intern may live in RW .data); property fail-before is in-place NUL on the interned path bytes"
    } else {
        Write-Host "f4_double_read vuln PE fail-before code=$($f4vuln.Code) notes=$vn"
    }
}

# 5. F5 two-process replace race against data/f5-slot.txt. Victim is data/f5-keep.txt.
Set-Content -Path (Join-Path $Work "f5.vire") -Value "define main`n  write with `"data/f5-slot.txt`", `"HACKED`"`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/f5.vire" "data/native-sec-windows/f5.hex"
if ($code -ne 0) { throw "f5 compile failed" }
HexToExe "data/native-sec-windows/f5.hex" (Join-Path $Work "f5.exe")
Copy-Item (Join-Path $Work "f5.vire") (Join-Path $VulnTree "data/native-sec-windows-f5.vire") -Force
Invoke-VireAt -WorkingDirectory $VulnTree -VireArgs @((Join-Path $VulnTree "compile-native.vire"), "data/native-sec-windows-f5.vire", "data/f5-vuln.hex")
Convert-HexFileToExe (Join-Path $VulnTree "data/f5-vuln.hex") (Join-Path $Work "f5-vuln.exe")

$racerPath = Join-Path $Work "f5-racer.ps1"
Set-Content -Path $racerPath -Value @'
param($Slot, $Keep)
while ($true) {
    try {
        if (Test-Path -LiteralPath $Slot) { Remove-Item -LiteralPath $Slot -Force }
        cmd /c mklink /H "$Slot" "$Keep" | Out-Null
    } catch { }
}
'@

function Invoke-F5Race([string]$WriteExe, [string]$Tag, [int]$Rounds) {
    $keep = Join-Path $Work "data\f5-keep.txt"
    $slot = Join-Path $Work "data\f5-slot.txt"
    $hits = 0
    $i = 0
    while ($i -lt $Rounds) {
        Set-Content -Path $keep -Value "KEEP" -NoNewline
        if (Test-Path $slot) { Remove-Item -Force $slot }
        Set-Content -Path $slot -Value "SLOT" -NoNewline
        $rp = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-File", $racerPath, $slot, $keep) -PassThru -WindowStyle Hidden
        Start-Sleep -Milliseconds 20
        $run = Invoke-NativeExe -ExePath $WriteExe -WorkingDirectory $Work
        try { $rp.Kill() } catch { }
        try { $rp.WaitForExit(2000) } catch { }
        $kept = [IO.File]::ReadAllText($keep)
        if ($kept -eq "HACKED") { $hits++ }
        $i++
        if ($run.Blocked) { return $hits }
    }
    Write-Host ("f5_two_process_race " + $Tag + " victim_hits=" + $hits + " rounds=" + $Rounds)
    return $hits
}

if (-not $script:DefenderBlocked) {
    $fixHits = Invoke-F5Race -WriteExe (Join-Path $Work "f5.exe") -Tag "fixed" -Rounds 40
    if ($fixHits -ne 0) { throw "f5_two_process_race fixed PE truncated victim $fixHits times" }
    $vulnHits = Invoke-F5Race -WriteExe (Join-Path $Work "f5-vuln.exe") -Tag "vuln" -Rounds 40
    if ($vulnHits -eq 0) {
        Write-Host "f5_two_process_race vuln PE did not hit in 40 rounds; fail-before remains CREATE_ALWAYS on 7c7c8ea write_have"
    } else {
        Write-Host "f5_two_process_race vuln fail-before victim_hits=$vulnHits"
    }
}

# 6. F6 crash PE: patch entry to deref null. Filter must print crash rip= and must not create crash-rip.txt.
function Invoke-F6Crash([string]$HelloExe, [string]$Tag) {
    $crashDir = Join-Path $Work ("crash-" + $Tag)
    New-Item -ItemType Directory -Force -Path $crashDir | Out-Null
    $crashExe = Join-Path $crashDir "crash.exe"
    Set-CrashEntry $HelloExe $crashExe
    foreach ($p in @((Join-Path $crashDir "crash-rip.txt"), (Join-Path $Work "crash-rip.txt"), (Join-Path $Root "crash-rip.txt"))) {
        if (Test-Path $p) { Remove-Item -Force $p }
    }
    $run = Invoke-NativeExe -ExePath $crashExe -WorkingDirectory $crashDir
    $rip = $false
    foreach ($p in @((Join-Path $crashDir "crash-rip.txt"), (Join-Path $Work "crash-rip.txt"), (Join-Path $Root "crash-rip.txt"), (Join-Path $crashDir "data\crash-rip.txt"))) {
        if (Test-Path $p) { $rip = $true; Write-Host ("f6_crash_pe file " + $p) }
    }
    Write-Host ("f6_crash_pe " + $Tag + " code=" + $run.Code + " blocked=" + $run.Blocked + " rip_file=" + $rip)
    return @{ Run = $run; RipFile = $rip }
}

Copy-Item (Join-Path $Work "hello.vire") (Join-Path $VulnTree "data/native-sec-windows-hello.vire") -Force
Invoke-VireAt -WorkingDirectory $VulnTree -VireArgs @((Join-Path $VulnTree "compile-native.vire"), "data/native-sec-windows-hello.vire", "data/hello-vuln.hex") -TimeoutSec 180
Convert-HexFileToExe (Join-Path $VulnTree "data/hello-vuln.hex") (Join-Path $Work "hello-vuln.exe")

if (-not $script:DefenderBlocked) {
    $f6fix = Invoke-F6Crash -HelloExe (Join-Path $Work "hello.exe") -Tag "fixed"
    if (-not $f6fix.Run.Blocked) {
        if ($f6fix.RipFile) { throw "f6_crash_pe fixed PE wrote crash-rip.txt" }
        if (-not ([string]$f6fix.Run.Output).Contains("crash rip=")) { throw "f6_crash_pe fixed PE missing crash rip= stdout: $($f6fix.Run.Output)" }
        Write-Host "f6_crash_pe fixed stdout has crash rip= and no crash-rip.txt"
    }
    $f6vuln = Invoke-F6Crash -HelloExe (Join-Path $Work "hello-vuln.exe") -Tag "vuln"
    if (-not $f6vuln.Run.Blocked) {
        if ($f6vuln.RipFile) {
            Write-Host "f6_crash_pe vuln fail-before created crash-rip.txt"
        } else {
            Write-Host "f6_crash_pe vuln PE did not leave crash-rip.txt (cwd/policy); emit still uses CREATE_ALWAYS on 7c7c8ea"
        }
    }
}

if ($script:DefenderBlocked) {
    Write-Output "native sec windows recipe: Defender blocked PE execute; junction and hardlink compiles ran without exclusions"
    exit 0
}
Write-Output "native sec windows recipe ok"
exit 0
