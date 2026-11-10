param(
    [ValidateSet("bootstrap", "prove", "all")]
    [string]$Phase = "prove",
    [string]$ExpectedEqualSha = "48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"

$BannedExeNames = @(
    "dotnet", "csc", "msbuild", "vbcscompiler", "corerun", "coreclr",
    "gcc", "g++", "clang", "clang++", "clang-cl", "ld", "as", "mingw32-make",
    "java", "javac", "cl", "link", "ildasm", "ilasm"
)
$BannedPathNeedles = @(
    "\dotnet",
    "\Microsoft Visual Studio",
    "\mingw",
    "\LLVM\",
    "\Java\",
    "\jdk",
    "\Microsoft.NET"
)
function Get-RequiredKernel32 {
    $pe = Join-Path $Root "src/pe.vire"
    $text = [System.IO.File]::ReadAllText($pe)
    if ($text -notmatch 'let names be \[([^\]]+)\]') {
        throw "src/pe.vire has no let names be list"
    }
    $names = [regex]::Matches($Matches[1], '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    if ($names.Count -lt 1) { throw "src/pe.vire names list is empty" }
    return @($names)
}
$RequiredKernel32 = Get-RequiredKernel32

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Get-RvaFileOffset([byte[]]$Bytes, [int]$E, [uint32]$Rva) {
    $opt = $E + 24
    $sizeOpt = [BitConverter]::ToUInt16($Bytes, $E + 20)
    $nsect = [BitConverter]::ToUInt16($Bytes, $E + 6)
    $sect = $opt + $sizeOpt
    for ($i = 0; $i -lt $nsect; $i++) {
        $off = $sect + ($i * 40)
        $vsize = [BitConverter]::ToUInt32($Bytes, $off + 8)
        $vaddr = [BitConverter]::ToUInt32($Bytes, $off + 12)
        $rawSize = [BitConverter]::ToUInt32($Bytes, $off + 16)
        $rawPtr = [BitConverter]::ToUInt32($Bytes, $off + 20)
        $span = $vsize
        if ($rawSize -gt $span) { $span = $rawSize }
        if ($Rva -ge $vaddr -and $Rva -lt ($vaddr + $span)) {
            return [int]($rawPtr + ($Rva - $vaddr))
        }
    }
    throw "rva $Rva not in a section"
}

function Get-CString([byte[]]$Bytes, [int]$Offset) {
    $end = $Offset
    while ($end -lt $Bytes.Length -and $Bytes[$end] -ne 0) { $end++ }
    if ($end -eq $Offset) { return "" }
    return [System.Text.Encoding]::ASCII.GetString($Bytes, $Offset, $end - $Offset)
}

function Get-PeImports([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw "not MZ $Path" }
    $e = [BitConverter]::ToInt32($bytes, 60)
    if ($e -lt 0 -or ($e + 24) -ge $bytes.Length) { throw "bad e_lfanew $Path" }
    if ([BitConverter]::ToUInt32($bytes, $e) -ne 0x4550) { throw "not PE $Path" }
    $opt = $e + 24
    $magic = [BitConverter]::ToUInt16($bytes, $opt)
    if ($magic -ne 0x20b) { throw "not PE32+ $Path" }
    $importRva = [BitConverter]::ToUInt32($bytes, $opt + 120)
    $importSize = [BitConverter]::ToUInt32($bytes, $opt + 124)
    $dlls = @{}
    if ($importRva -eq 0 -or $importSize -eq 0) {
        return $dlls
    }
    $desc = Get-RvaFileOffset $bytes $e $importRva
    while ($true) {
        $ilt = [BitConverter]::ToUInt32($bytes, $desc)
        $nameRva = [BitConverter]::ToUInt32($bytes, $desc + 12)
        $iat = [BitConverter]::ToUInt32($bytes, $desc + 16)
        if ($ilt -eq 0 -and $nameRva -eq 0 -and $iat -eq 0) { break }
        $dll = (Get-CString $bytes (Get-RvaFileOffset $bytes $e $nameRva)).ToLowerInvariant()
        $names = New-Object System.Collections.Generic.List[string]
        $thunkRva = $ilt
        if ($thunkRva -eq 0) { $thunkRva = $iat }
        $thunk = Get-RvaFileOffset $bytes $e $thunkRva
        while ($true) {
            $entry = [BitConverter]::ToUInt64($bytes, $thunk)
            if ($entry -eq 0) { break }
            if (($entry -band 0x8000000000000000) -ne 0) {
                $names.Add("#" + ($entry -band 0xFFFF))
            } else {
                $hintOff = Get-RvaFileOffset $bytes $e ([uint32]($entry -band 0x7FFFFFFF))
                $names.Add((Get-CString $bytes ($hintOff + 2)))
            }
            $thunk += 8
        }
        $dlls[$dll] = $names
        $desc += 20
    }
    return $dlls
}

function Assert-Gen1Imports([string]$ExePath) {
    $imports = Get-PeImports $ExePath
    Write-Host "pe_imports_dlls $($imports.Keys -join ',')"
    if ($imports.Count -ne 1 -or -not $imports.ContainsKey("kernel32.dll")) {
        throw "gen1 IAT must be kernel32.dll only, got $($imports.Keys -join ',')"
    }
    $got = @($imports["kernel32.dll"])
    Write-Host ("pe_imports_kernel32 " + ($got -join ","))
    foreach ($need in $RequiredKernel32) {
        if ($got -notcontains $need) { throw "missing kernel32 import $need" }
    }
    $extra = @($got | Where-Object { $RequiredKernel32 -notcontains $_ })
    if ($extra.Count -gt 0) { throw "unexpected kernel32 import $($extra -join ',')" }
    foreach ($dll in $imports.Keys) {
        if ($dll -match "coreclr|mscoree|clrjit|hostfxr|hostpolicy") {
            throw "PE imports a .NET runtime library: $dll"
        }
    }
}

function Get-IsolatedPath {
    $keep = @()
    foreach ($part in ($env:Path -split ";")) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $hit = $false
        foreach ($needle in $BannedPathNeedles) {
            if ($part -like "*$needle*") { $hit = $true; break }
        }
        if (-not $hit) { $keep += $part }
    }
    $must = @(
        "$env:WINDIR\System32",
        "$env:WINDIR",
        "$env:WINDIR\System32\WindowsPowerShell\v1.0"
    )
    foreach ($m in $must) {
        if ($keep -notcontains $m) { $keep += $m }
    }
    return ($keep -join ";")
}

function Write-EnvCapture([string]$OutFile, [string]$IsolatedPath) {
    $lines = @()
    $lines += "machine_path=$env:Path"
    $lines += "isolated_path=$IsolatedPath"
    foreach ($name in @("dotnet", "gcc", "clang", "cl", "javac", "java", "mingw32-make")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $lines += "machine_has_$name=$($cmd.Source)" }
        else { $lines += "machine_has_$name=absent" }
    }
    $saved = $env:Path
    $env:Path = $IsolatedPath
    try {
        foreach ($name in @("dotnet", "gcc", "clang", "cl", "javac", "java", "mingw32-make")) {
            $cmd = Get-Command $name -ErrorAction SilentlyContinue
            if ($cmd) { throw "isolated PATH still resolves $name -> $($cmd.Source)" }
            $lines += "isolated_has_$name=absent"
        }
    } finally {
        $env:Path = $saved
    }
    [System.IO.File]::WriteAllLines($OutFile, $lines)
    Get-Content $OutFile | ForEach-Object { Write-Host $_ }
}

function Get-ProcessKids([int]$ParentId) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ParentId" -ErrorAction Stop
}

function Invoke-Isolated {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$TimeoutSec,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)][hashtable]$EnvTable
    )
    $data = Join-Path $Root "data"
    $stamp = Join-Path $data ("clean-" + $Name)
    $outFile = "$stamp.out.txt"
    $errFile = "$stamp.err.txt"
    $inFile = "$stamp.in.txt"
    Set-Content -Path $inFile -Value "" -NoNewline
    if (Test-Path $outFile) { Remove-Item -Force $outFile }
    if (Test-Path $errFile) { Remove-Item -Force $errFile }
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($FilePath).ToLowerInvariant()
    foreach ($b in $BannedExeNames) {
        if ($leaf -eq $b) { throw "$Name refused to launch banned $leaf" }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($ArgumentList) {
        foreach ($a in $ArgumentList) { [void]$psi.ArgumentList.Add($a) }
    }
    $psi.Environment.Clear()
    foreach ($k in $EnvTable.Keys) { $psi.Environment[$k] = [string]$EnvTable[$k] }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdin = $p.StandardInput
    $stdin.Close()
    $kidsBad = @()
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
    while (-not $p.HasExited) {
        if ([datetime]::UtcNow -gt $deadline) {
            try { $p.Kill($true) } catch { }
            throw "$Name timed out after ${TimeoutSec}s"
        }
        foreach ($kid in (Get-ProcessKids $p.Id)) {
            $kl = [System.IO.Path]::GetFileNameWithoutExtension([string]$kid.Name).ToLowerInvariant()
            if ($BannedExeNames -contains $kl) {
                $kidsBad += "$($kid.Name) $($kid.CommandLine)"
            }
        }
        Start-Sleep -Milliseconds 50
    }
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    [System.IO.File]::WriteAllText($outFile, $stdout)
    [System.IO.File]::WriteAllText($errFile, $stderr)
    Write-Host ("step_" + $Name + "_exit " + $p.ExitCode)
    Write-Host ("step_" + $Name + "_file " + $FilePath)
    if ($stderr) { Write-Host $stderr.TrimEnd() }
    if ($stdout) { Write-Host $stdout.TrimEnd() }
    if ($kidsBad.Count -gt 0) { throw "$Name launched banned child: $($kidsBad -join '; ')" }
    if ($p.ExitCode -ne 0) { throw "$Name exit $($p.ExitCode)" }
    return @{ StdOut = $stdout; StdErr = $stderr }
}

function Invoke-Bootstrap {
    $handoff = Join-Path $PSScriptRoot "native-selfhost-handoff.ps1"
    Write-Host "phase_bootstrap start (explicit .NET interpreter emit)"
    Write-Host "bootstrap_cmd pwsh -File $handoff"
    & $handoff
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "bootstrap handoff exit $LASTEXITCODE" }
    Write-Host "phase_bootstrap ok"
}

function New-IsolatedEnv {
    $path = Get-IsolatedPath
    $table = @{}
    foreach ($entry in [System.Environment]::GetEnvironmentVariables("Process").GetEnumerator()) {
        $skip = $false
        foreach ($needle in $BannedPathNeedles) {
            if ([string]$entry.Value -like "*$needle*") { $skip = $true; break }
        }
        if ($skip) { continue }
        if ($entry.Key -eq "Path") { continue }
        $table[$entry.Key] = [string]$entry.Value
    }
    $table["Path"] = $path
    $table["VIRE_BUDGET"] = "5000000"
    $table["VIRE_HEADLESS"] = "1"
    foreach ($need in @("SystemRoot", "WINDIR", "ComSpec", "PATHEXT", "TEMP", "TMP", "USERPROFILE", "HOMEDRIVE", "HOMEPATH", "SystemDrive", "PROCESSOR_ARCHITECTURE", "NUMBER_OF_PROCESSORS")) {
        $val = [Environment]::GetEnvironmentVariable($need)
        if ($val) { $table[$need] = $val }
    }
    return @{ Path = $path; Table = $table }
}

function Invoke-Prove {
    $data = Join-Path $Root "data"
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    $gen1Exe = Join-Path $data "gen1.exe"
    $gen1Hex = Join-Path $data "gen1.hex"
    if (-not (Test-Path $gen1Exe)) { throw "missing $gen1Exe; run -Phase bootstrap first. prove must not call dotnet." }
    if (-not (Test-Path $gen1Hex)) { throw "missing $gen1Hex" }
    $guest = Join-Path $Root "guest-hello.vire"
    $dataGuest = Join-Path $data "guest-hello.vire"
    Copy-Item $guest $dataGuest -Force
    $compiler = Join-Path $data "compile-native.vire"
    if (-not (Test-Path $compiler)) {
        Copy-Item (Join-Path $Root "compile-native.vire") $compiler -Force
    }
    $src = Join-Path $data "src"
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    foreach ($name in @("asm.vire", "pe.vire", "rt.vire", "rt-more.vire")) {
        $dst = Join-Path $src $name
        if (-not (Test-Path $dst)) {
            Copy-Item (Join-Path $Root "src/$name") $dst -Force
        }
    }

    Write-Host "phase_isolate start"
    Assert-Gen1Imports $gen1Exe
    $iso = New-IsolatedEnv
    $capture = Join-Path $data "clean-env-capture.txt"
    Write-EnvCapture $capture $iso.Path
    Write-Host "phase_isolate ok"

    Write-Host "phase_native start"
    $helloHex = Join-Path $data "clean-hello.hex"
    $helloExe = Join-Path $data "clean-hello.exe"
    if (Test-Path $helloHex) { Remove-Item -Force $helloHex }
    $r = Invoke-Isolated -Name "gen1_hello" -TimeoutSec 120 -FilePath $gen1Exe -ArgumentList @(
        "data/guest-hello.vire", "data/clean-hello.hex"
    ) -EnvTable $iso.Table
    if ($r.StdOut -notmatch "compiled") { throw "gen1_hello missing compiled" }
    Convert-HexToExe $helloHex $helloExe
    Assert-Gen1Imports $helloExe
    $r = Invoke-Isolated -Name "gen1_hello_run" -TimeoutSec 15 -FilePath $helloExe -ArgumentList @() -EnvTable $iso.Table
    if ($r.StdOut.Trim() -ne "hello from stage") { throw "gen1_hello_run stdout $($r.StdOut)" }

    $gen2Hex = Join-Path $data "clean-gen2.hex"
    if (Test-Path $gen2Hex) { Remove-Item -Force $gen2Hex }
    $r = Invoke-Isolated -Name "gen2_native" -TimeoutSec 600 -FilePath $gen1Exe -ArgumentList @(
        "data/compile-native.vire", "data/clean-gen2.hex"
    ) -EnvTable $iso.Table
    if ($r.StdOut -notmatch "compiled") { throw "gen2_native missing compiled" }
    $h1 = (Get-FileHash -Algorithm SHA256 $gen1Hex).Hash.ToLowerInvariant()
    $h2 = (Get-FileHash -Algorithm SHA256 $gen2Hex).Hash.ToLowerInvariant()
    Write-Host "gen1_sha256 $h1"
    Write-Host "gen2_sha256 $h2"
    if ($h1 -ne $h2) { throw "gen1/gen2 SHA-256 differ" }
    if ($h1 -ne $ExpectedEqualSha.ToLowerInvariant()) {
        Write-Host "note_sha_differs_from_pr42_baseline $ExpectedEqualSha (equal hashes still hold)"
    }
    Write-Host "phase_native ok"

    $sourceSha = "unknown"
    try { $sourceSha = (git -C $Root rev-parse HEAD).Trim() } catch { }
    $exeHash = (Get-FileHash -Algorithm SHA256 $gen1Exe).Hash.ToLowerInvariant()
    $pkg = Join-Path $data "native-clean-machine-pkg"
    if (Test-Path $pkg) { Remove-Item -Recurse -Force $pkg }
    $pkgData = Join-Path $pkg "data"
    $pkgSrc = Join-Path $pkgData "src"
    New-Item -ItemType Directory -Path $pkgSrc -Force | Out-Null
    Copy-Item $gen1Exe (Join-Path $pkg "gen1.exe")
    Copy-Item $gen1Hex (Join-Path $pkgData "gen1.hex")
    Copy-Item $gen2Hex (Join-Path $pkgData "gen2.hex")
    Copy-Item $compiler (Join-Path $pkgData "compile-native.vire")
    Copy-Item $dataGuest (Join-Path $pkgData "guest-hello.vire")
    Copy-Item (Join-Path $src "*") $pkgSrc
    Copy-Item $capture (Join-Path $pkg "clean-env-capture.txt")
    $manifest = @"
source_sha=$sourceSha
pr42_pin=3d9fc58c80629f1fd6ac11b3576831f5c869087d
layout=gen1.exe at package root; compiler guest is data/compile-native.vire; runtime sources are data/src/*.vire
run_cwd=package root (same join as CI: use src/pe.vire from a data/ guest becomes data/src/pe.vire)
native_read=paths must start with data/ or site/; a root compile-native.vire will not load src/
trust_chain=source -> dotnet exec vire.dll compile-native.vire (bootstrap interpreter) -> gen1.hex -> PowerShell hex-to-bytes (conversion) -> gen1.exe -> gen1.exe data/compile-native.vire -> data/gen2.hex
equal_hash_of=hex files, not a second hash of the .exe
bootstrap_is_not_native=true
single_file_dotnet_publish_is_not_native=true
unicorn_is_not_windows_gate=true
vc_bytecode_is_not_native=true
gen1_exe_sha256=$exeHash
gen1_hex_sha256=$h1
gen2_hex_sha256=$h2
equal=$($h1 -eq $h2)
os_libraries=kernel32.dll ($($RequiredKernel32 -join ', '))
caps=arena 32MB VirtualAlloc, host list 100000, ProgramStepCap 5000000; host compile-native.vire uses CompilerStepCap 50000000 and ignores VIRE_BUDGET
hex_to_exe=PowerShell conversion of compiler hex, not gcc/clang/dotnet compile
"@
    [System.IO.File]::WriteAllText((Join-Path $pkg "MANIFEST.txt"), $manifest)
    Write-Host $manifest
    $zip = Join-Path $data "native-clean-machine.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($pkg, $zip)
    Write-Host "package_zip $zip"
    Write-Host "native clean machine prove ok"
}

switch ($Phase) {
    "bootstrap" { Invoke-Bootstrap }
    "prove" { Invoke-Prove }
    "all" { Invoke-Bootstrap; Invoke-Prove }
}
