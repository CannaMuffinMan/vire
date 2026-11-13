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
    $hostArgs = $VireArgs
    $leaf = [IO.Path]::GetFileName($VireArgs[0])
    $savedBudget = $env:VIRE_BUDGET
    if ($leaf -eq "compile-native.vire" -or $leaf -eq "compiler.vire") {
        $hostArgs = @("--compiler") + $VireArgs
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    }
    $argList = @("exec", $VireDll) + $hostArgs
    try {
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
    } finally {
        if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
    }
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

# Host C# check-then-open TOCTOU (interpreter, not PE). Fail-before: DataOrSite then File.AppendAllText.
$hostDir = Join-Path $Work "host-toctou"
New-Item -ItemType Directory -Force -Path (Join-Path $hostDir "data") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $hostDir "outside") | Out-Null
Set-Content -Path (Join-Path $hostDir "data\note.txt") -Value "SECRET-KEEP-ME-LONG" -NoNewline
Set-Content -Path (Join-Path $hostDir "outside\note.txt") -Value "OUTSIDE-KEEP" -NoNewline
Set-Content -Path (Join-Path $hostDir "append.vire") -Value "can fs.write data`ndefine main`n  append with `"data/note.txt`", `"PWN`"`nend`n"
$dataHost = Join-Path $hostDir "data"
$outHost = Join-Path $hostDir "outside"
$checkedPath = [IO.Path]::GetFullPath((Join-Path $dataHost "note.txt"))
Rename-Item -LiteralPath $dataHost -NewName "data.real"
cmd /c mklink /J "$dataHost" "$outHost" | Out-Null
[IO.File]::AppendAllText($checkedPath, "PWN-BEFORE")
$beforeTxt = [IO.File]::ReadAllText($checkedPath)
Write-Host ("host_toctou_fail_before outside=" + $beforeTxt)
if (-not $beforeTxt.Contains("PWN-BEFORE")) { throw "host TOCTOU fail-before: File.AppendAllText after junction did not follow the swap" }
cmd /c rmdir "$dataHost" | Out-Null
Rename-Item -LiteralPath (Join-Path $hostDir "data.real") -NewName "data"
Set-Content -Path (Join-Path $hostDir "data\note.txt") -Value "SECRET-KEEP-ME-LONG" -NoNewline
Set-Content -Path (Join-Path $hostDir "outside\note.txt") -Value "OUTSIDE-KEEP" -NoNewline
Rename-Item -LiteralPath $dataHost -NewName "data.real"
cmd /c mklink /J "$dataHost" "$outHost" | Out-Null
$code = Invoke-Vire -TimeoutSec 30 (Join-Path $hostDir "append.vire")
if (Test-Path (Join-Path $outHost "note.txt")) {
    $hostOutside = [IO.File]::ReadAllText((Join-Path $outHost "note.txt"))
} else { $hostOutside = "" }
Write-Host ("host_toctou_fixed outside=" + $hostOutside + " code=" + $code)
if ($hostOutside.Contains("PWN")) { throw "host TOCTOU pass-after failed: interpreter wrote outside" }
cmd /c rmdir "$dataHost" | Out-Null
if (Test-Path (Join-Path $hostDir "data.real")) { Rename-Item -LiteralPath (Join-Path $hostDir "data.real") -NewName "data" }

# Trailing dot/space native refuse on the product PE.
Set-Content -Path (Join-Path $Work "dotbat.vire") -Value "can fs.write data`ndefine main`n  write with `"data/payload.bat.`", `"pwn`"`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-sec-windows/dotbat.vire" "data/native-sec-windows/dotbat.hex"
if ($code -ne 0) { throw "dotbat compile failed" }
HexToExe "data/native-sec-windows/dotbat.hex" (Join-Path $Work "dotbat.exe")
New-Item -ItemType Directory -Force -Path (Join-Path $Work "data") | Out-Null
$dotRun = Invoke-NativeExe -ExePath (Join-Path $Work "dotbat.exe") -WorkingDirectory $Work
if (-not $dotRun.Blocked) {
    if ($dotRun.Code -eq 0) { throw "trailing-dot write PE must fail closed" }
    if (Test-Path (Join-Path $Work "data\payload.bat")) { throw "trailing dot created payload.bat" }
    if (Test-Path (Join-Path $Work "data\payload.bat.")) { throw "trailing dot created payload.bat." }
    Write-Host "native_trailing_dot refused"
}

# 2. Parent directory junction. Compile always; execute only if Defender allows.
$outside = Join-Path $Work "outside"
New-Item -ItemType Directory -Path $outside | Out-Null
Set-Content -Path (Join-Path $outside "secret.txt") -Value "outside-secret" -NoNewline
$link = Join-Path $Work "data"
if (Test-Path $link) { Remove-Item -Recurse -Force $link }
cmd /c mklink /J "$link" "$outside"
if ($LASTEXITCODE -ne 0) { throw "junction skipped or failed" }
Set-Content -Path (Join-Path $Work "read.vire") -Value "can fs.read data`ndefine main`n  say (read with `"data/secret.txt`")`nend`n"
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
Set-Content -Path (Join-Path $Work "write.vire") -Value "can fs.write data`ndefine main`n  write with `"data/note.txt`", `"hacked`"`nend`n"
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

function Get-ShaTree([string]$sha) {
    $dir = [string](Join-Path ([IO.Path]::GetTempPath()) ("vire-tree-" + $sha.Substring(0, 12)))
    if (-not (Test-Path -LiteralPath (Join-Path $dir "compile-native.vire"))) {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        # git writes to the success stream; do not let that become the function output (Copy-Item Destination Object[]).
        & git worktree add --detach $dir $sha 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            & git fetch --depth 1 origin $sha 2>&1 | ForEach-Object { Write-Host $_ }
            & git worktree add --detach $dir $sha 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { throw "git worktree add $dir $sha failed" }
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dir "compile-native.vire"))) { throw "tree missing compile-native.vire: $sha $dir" }
    return [string]$dir
}

function Get-VulnTree {
    return [string](Get-ShaTree "7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867")
}

# Test-only. Never apply to the product checkout. Sleep(400) between rt_check_path (GFA walk) and CreateFileA.
function Apply-SecWiden([string]$Tree) {
    $peFiles = @((Join-Path $Tree "src/pe.vire"), (Join-Path $Tree "data/src/pe.vire"))
    foreach ($pe in $peFiles) {
        if (-not (Test-Path -LiteralPath $pe)) { continue }
        $t = [IO.File]::ReadAllText($pe)
        if ($t.Contains('"Sleep"')) { continue }
        if ($t.Contains("GetFinalPathNameByHandleA")) {
            $t = $t.Replace('"GetFinalPathNameByHandleA"]', '"GetFinalPathNameByHandleA", "Sleep"]')
            $t = $t.Replace('"ilt_fp"]', '"ilt_fp", "ilt_sl"]')
            $t = $t.Replace('"iat_fp"]', '"iat_fp", "iat_sl"]')
            $t = $t.Replace('"hint_fp"]', '"hint_fp", "hint_sl"]')
        } else {
            $t = $t.Replace('"SetEndOfFile"]', '"SetEndOfFile", "Sleep"]')
            $t = $t.Replace('"ilt_se"]', '"ilt_se", "ilt_sl"]')
            $t = $t.Replace('"iat_se"]', '"iat_se", "iat_sl"]')
            $t = $t.Replace('"hint_se"]', '"hint_se", "hint_sl"]')
        }
        if (-not $t.Contains('"Sleep"')) { throw "sec widen IAT insert failed in $pe" }
        [IO.File]::WriteAllText($pe, $t)
    }
    $needle = "  emitCallTo with image, fixes, `"rt_check_path`"`n  emitList with image, [72, 139, 77, 232]`n  emitCallTo with image, fixes, `"rt_banned`""
    $insert = "  emitCallTo with image, fixes, `"rt_check_path`"`n  emitList with image, [185]`n  emitU32 with image, 400`n  emitList with image, [255, 21]`n  emitRel with image, fixes, `"iat_sl`"`n  emitList with image, [72, 139, 77, 232]`n  emitCallTo with image, fixes, `"rt_banned`""
    $hit = 0
    foreach ($more in @((Join-Path $Tree "src/rt-more.vire"), (Join-Path $Tree "data/src/rt-more.vire"))) {
        if (-not (Test-Path -LiteralPath $more)) { continue }
        $t = [IO.File]::ReadAllText($more).Replace("`r`n", "`n")
        if ($t.Contains("iat_sl")) { $hit = $hit + 1; continue }
        if (-not $t.Contains($needle)) { throw "sec widen insert point missing in $more" }
        $t = $t.Replace($needle, $insert)
        [IO.File]::WriteAllText($more, $t.Replace("`n", "`r`n"))
        $hit = $hit + 1
    }
    if ($hit -lt 1) { throw "sec widen applied to no rt-more.vire in $Tree" }
    Write-Host ("sec_widen applied " + $Tree)
}

function Invoke-VireAt {
    param([string]$WorkingDirectory, [string[]]$VireArgs, [int]$TimeoutSec = 180)
    $outFile = Join-Path $Work ("at-" + [guid]::NewGuid().ToString("N") + ".out")
    $errFile = "$outFile.err"
    $inFile = "$outFile.in"
    Set-Content -Path $inFile -Value "" -NoNewline
    $hostArgs = $VireArgs
    $leaf = [IO.Path]::GetFileName($VireArgs[0])
    $savedBudget = $env:VIRE_BUDGET
    if ($leaf -eq "compile-native.vire" -or $leaf -eq "compiler.vire") {
        $hostArgs = @("--compiler") + $VireArgs
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    }
    $argList = @("exec", $VireDll) + $hostArgs
    try {
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
    } finally {
        if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
    }
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

# Trailing-dot fail-before: Win32 CreateFile/WriteAllText strips the trailing dot to payload.bat.
$stripDir = Join-Path $Work "dot-strip"
New-Item -ItemType Directory -Force -Path (Join-Path $stripDir "data") | Out-Null
[IO.File]::WriteAllText((Join-Path $stripDir "data\payload.bat."), "pwn")
$stripped = Test-Path (Join-Path $stripDir "data\payload.bat")
Write-Host ("native_trailing_dot_fail_before win32_strip_bat=" + $stripped)
if (-not $stripped) { throw "trailing-dot fail-before: Windows did not strip payload.bat. to payload.bat" }

# 4. F4: intern section named; RW mutation vs RX AV. Same cell via let p.
New-Item -ItemType Directory -Force -Path (Join-Path $Work "data\f4") | Out-Null
Set-Content -Path (Join-Path $Work "data\f4\note.txt") -Value "NOTE" -NoNewline
Set-Content -Path (Join-Path $Work "f4.vire") -Value "can fs.read data`ndefine main`n  let p be `"data/f4/note.txt`"`n  say (read with p)`n  say (read with p)`nend`n"
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

# 5/walk: deterministic parent-junction race uses a test-only Sleep widener on
# isolated 3d9fc58 + HEAD worktrees (Apply-SecWiden). Product compile-native is unchanged.

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

# Widened F5 + walk: same Sleep inserted in 3d9fc58 and HEAD worktrees only.
$RaceVuln = [string](Get-ShaTree "3d9fc58c80629f1fd6ac11b3576831f5c869087d")
Apply-SecWiden $RaceVuln
$headSha = ([string](& git rev-parse HEAD)).Trim()
$RaceFix = [string](Get-ShaTree $headSha)
Apply-SecWiden $RaceFix
Write-Host ("sec_widen_vuln_tree " + $RaceVuln)
Write-Host ("sec_widen_fix_tree " + $RaceFix)

function Compile-WidenGuest([string]$Tree, [string]$SrcName, [string]$Body, [string]$ExePath) {
    $data = Join-Path $Tree "data"
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    Set-Content -Path (Join-Path $data $SrcName) -Value $Body
    Invoke-VireAt -WorkingDirectory $Tree -VireArgs @((Join-Path $Tree "compile-native.vire"), ("data/" + $SrcName), ("data/" + $SrcName + ".hex"))
    Convert-HexFileToExe (Join-Path $data ($SrcName + ".hex")) $ExePath
}

$f5Body = "can fs.write data`ndefine main`n  write with `"data/f5-slot.txt`", `"HACKED`"`nend`n"
$walkBody = "can fs.write data`ndefine main`n  write with `"data/note.txt`", `"hacked`"`nend`n"
Compile-WidenGuest $RaceVuln "f5-widen.vire" $f5Body (Join-Path $Work "f5-vuln.exe")
Compile-WidenGuest $RaceFix "f5-widen.vire" $f5Body (Join-Path $Work "f5.exe")
Compile-WidenGuest $RaceVuln "walk-widen.vire" $walkBody (Join-Path $Work "walk-vuln.exe")
Compile-WidenGuest $RaceFix "walk-widen.vire" $walkBody (Join-Path $Work "walk.exe")

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
    Set-Content -Path (Join-Path $Work "data\f5-slot.txt") -Value "SLOT" -NoNewline
    Set-Content -Path (Join-Path $outside "note.txt") -Value "SECRET-KEEP-ME-LONG" -NoNewline
    Set-Content -Path (Join-Path $outside "f5-slot.txt") -Value "OUT-KEEP" -NoNewline
}

function Invoke-WalkSwapNow {
    $data = Join-Path $Work "data"
    $real = Join-Path $Work "data.real"
    $outside = Join-Path $Work "outside"
    if ((Test-Path -LiteralPath $data) -and -not (Test-Path -LiteralPath $real)) {
        Rename-Item -LiteralPath $data -NewName "data.real"
        cmd /c mklink /J "$data" "$outside" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "walk mklink /J data -> outside failed" }
    }
}

function Invoke-WidenJunctionRace([string]$WriteExe, [string]$Tag, [string]$OutsideLeaf, [string]$HitText) {
    Restore-WalkTree
    $tag = [guid]::NewGuid().ToString("N")
    $outFile = Join-Path $Work ("run-" + $tag + ".out")
    $errFile = Join-Path $Work ("run-" + $tag + ".err")
    $p = Start-Process -FilePath $WriteExe -WorkingDirectory $Work -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $swapped = $false
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 350 -and -not $p.HasExited) {
        Start-Sleep -Milliseconds 40
        try {
            Invoke-WalkSwapNow
            $swapped = $true
            break
        } catch { }
    }
    if (-not $p.WaitForExit(8000)) {
        try { $p.Kill($true) } catch { }
        throw "$Tag widen PE timed out"
    }
    $out = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
    $err = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
    if ($out) { Write-Host $out.TrimEnd() }
    if ($err) { Write-Host $err.TrimEnd() }
    $outsidePath = Join-Path $Work ("outside\" + $OutsideLeaf)
    $outsideText = if (Test-Path -LiteralPath $outsidePath) { [IO.File]::ReadAllText($outsidePath) } else { "" }
    Write-Host ("f_widen " + $Tag + " swapped=" + $swapped + " outside=" + $outsideText + " write_code=" + $p.ExitCode)
    if (Test-DefenderBlock -ErrorRecord $null -ExitCode $p.ExitCode -Output "$out $err") {
        throw "Defender blocked $Tag widen PE"
    }
    Restore-WalkTree
    return @{ Text = $outsideText; Code = $p.ExitCode; Swapped = $swapped }
}

$f5v = Invoke-WidenJunctionRace (Join-Path $Work "f5-vuln.exe") "f5-vuln" "f5-slot.txt" "HACKED"
if ($f5v.Text -ne "HACKED") { throw "f5 fail-before missing: 3d9fc58 widened PE did not write outside (got $($f5v.Text) code=$($f5v.Code)). 0/0 is a failed gate." }
Write-Host "f5_two_process_race vuln victim_hits=1 rounds=1 sec=0.400"
$f5f = Invoke-WidenJunctionRace (Join-Path $Work "f5.exe") "f5-fixed" "f5-slot.txt" "HACKED"
if ($f5f.Text -eq "HACKED") { throw "f5 pass-after failed: fixed widened PE wrote outside" }
Write-Host "f5_two_process_race fixed victim_hits=0 rounds=1"

$wv = Invoke-WidenJunctionRace (Join-Path $Work "walk-vuln.exe") "walk-vuln" "note.txt" "hacked"
if ($wv.Text -ne "hacked") { throw "f_walk fail-before missing: 3d9fc58 widened PE did not write outside (got $($wv.Text) code=$($wv.Code)). 0/0 is a failed gate." }
Write-Host "f_walk_then_open vuln outside_hits=1 rounds=1 sec=0.400"
$wf = Invoke-WidenJunctionRace (Join-Path $Work "walk.exe") "walk-fixed" "note.txt" "hacked"
if ($wf.Text -eq "hacked") { throw "f_walk pass-after failed: fixed PE wrote outside" }
Write-Host "f_walk_then_open fixed outside_hits=0 rounds=1"
Write-Host "f_walk_then_open GetFinalPathNameByHandle identity closed"

if ($script:DefenderBlocked) {
    Write-Output "native sec windows recipe: Defender blocked PE execute; junction and hardlink compiles ran without exclusions"
    exit 0
}
Write-Output "native sec windows recipe ok"
exit 0
