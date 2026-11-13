# Bounded native selfhost on Windows. PowerShell only.
# stage -> hello PE -> host gen1 -> gen1 hello PE -> gen1 gen2 -> SHA-256.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
$Src = Join-Path $Data "src"
New-Item -ItemType Directory -Force -Path $Src | Out-Null
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

function Invoke-Bounded {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$TimeoutSec,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [AllowEmptyCollection()]
        [string[]]$ArgumentList = @()
    )
    $stamp = Join-Path $Data ("handoff-" + $Name)
    $outFile = "$stamp.out.txt"
    $errFile = "$stamp.err.txt"
    $inFile = "$stamp.in.txt"
    Set-Content -Path $inFile -Value "" -NoNewline
    if (Test-Path $outFile) { Remove-Item -Force $outFile }
    if (Test-Path $errFile) { Remove-Item -Force $errFile }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $start = @{
        FilePath = $FilePath
        WorkingDirectory = $Root
        NoNewWindow = $true
        PassThru = $true
        RedirectStandardInput = $inFile
        RedirectStandardOutput = $outFile
        RedirectStandardError = $errFile
    }
    if ($ArgumentList -and $ArgumentList.Count -gt 0) { $start.ArgumentList = $ArgumentList }
    $p = Start-Process @start
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill($true) } catch { }
        $sw.Stop()
        throw "$Name timed out after $([int]$sw.Elapsed.TotalSeconds)s (limit ${TimeoutSec}s)"
    }
    $sw.Stop()
    $stdout = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
    $stderr = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
    Write-Host ("step_" + $Name + "_sec " + $sw.Elapsed.TotalSeconds.ToString("0.000"))
    Write-Host ("step_" + $Name + "_exit " + $p.ExitCode)
    if ($stderr) { Write-Host $stderr.TrimEnd() }
    if ($stdout) { Write-Host $stdout.TrimEnd() }
    if ($p.ExitCode -eq -1073741819 -or $p.ExitCode -eq 0xC0000005) {
        Write-Host "crash_access_violation $Name pid $($p.Id)"
        foreach ($ripFile in @((Join-Path $Root "crash-rip.txt"), (Join-Path $Data "crash-rip.txt"), (Join-Path $Root "data/crash-rip.txt"))) {
            if (Test-Path $ripFile) {
                Write-Host ("crash_rip_file " + $ripFile + " " + ((Get-Content -Raw $ripFile) -replace '\s+', ' '))
            }
        }
        try {
            Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; StartTime = (Get-Date).AddMinutes(-10) } -MaxEvents 5 -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host ("wer_app_error " + $_.TimeCreated + " " + ($_.Message -replace '\s+', ' ').Substring(0, [Math]::Min(800, $_.Message.Length))) }
        } catch {
            Write-Host "wer_event1000_query_failed $($_.Exception.Message)"
        }
    }
    if ($p.ExitCode -ne 0) { throw "$Name exit $($p.ExitCode)" }
    return @{ StdOut = $stdout; StdErr = $stderr; Sec = $sw.Elapsed.TotalSeconds }
}

Write-VireHostInfo

Copy-Item (Join-Path $Root "compile-native.vire") (Join-Path $Data "compile-native.vire") -Force
Copy-Item (Join-Path $Root "src/asm.vire") (Join-Path $Src "asm.vire") -Force
Copy-Item (Join-Path $Root "src/pe.vire") (Join-Path $Src "pe.vire") -Force
Copy-Item (Join-Path $Root "src/rt.vire") (Join-Path $Src "rt.vire") -Force
Copy-Item (Join-Path $Root "src/rt-more.vire") (Join-Path $Src "rt-more.vire") -Force
Copy-Item (Join-Path $Root "src/rt-net.vire") (Join-Path $Src "rt-net.vire") -Force
Copy-Item (Join-Path $Root "src/elf.vire") (Join-Path $Src "elf.vire") -Force
Copy-Item (Join-Path $Root "src/rt-linux.vire") (Join-Path $Src "rt-linux.vire") -Force
foreach ($blob in @(
    "rt-net-blob.txt", "rt-net-pins.txt", "rt-net-fixes.txt",
    "rt-net-json-blob.txt", "rt-net-json-pins.txt", "rt-net-json-fixes.txt"
)) {
    Copy-Item (Join-Path $Root "src/$blob") (Join-Path $Src $blob) -Force
}
Copy-Item (Join-Path $Root "guest-hello.vire") (Join-Path $Data "guest-hello.vire") -Force
$pairs = @(
    @("compile-native.vire", "data/compile-native.vire"),
    @("src/asm.vire", "data/src/asm.vire"),
    @("src/pe.vire", "data/src/pe.vire"),
    @("src/rt.vire", "data/src/rt.vire"),
    @("src/rt-more.vire", "data/src/rt-more.vire"),
    @("src/rt-net.vire", "data/src/rt-net.vire"),
    @("src/elf.vire", "data/src/elf.vire"),
    @("src/rt-linux.vire", "data/src/rt-linux.vire"),
    @("src/rt-net-blob.txt", "data/src/rt-net-blob.txt"),
    @("src/rt-net-pins.txt", "data/src/rt-net-pins.txt"),
    @("src/rt-net-fixes.txt", "data/src/rt-net-fixes.txt"),
    @("src/rt-net-json-blob.txt", "data/src/rt-net-json-blob.txt"),
    @("src/rt-net-json-pins.txt", "data/src/rt-net-json-pins.txt"),
    @("src/rt-net-json-fixes.txt", "data/src/rt-net-json-fixes.txt")
)
foreach ($pair in $pairs) {
    $ha = (Get-FileHash -Algorithm SHA256 (Join-Path $Root $pair[0])).Hash
    $hb = (Get-FileHash -Algorithm SHA256 (Join-Path $Root $pair[1])).Hash
    if ($ha -ne $hb) { throw "stage mismatch $($pair[0])" }
}
Write-Output "step_stage ok"

$helloHex = Join-Path $Data "guest-hello.hex"
$helloExe = Join-Path $Data "guest-hello.exe"
if (Test-Path $helloHex) { Remove-Item -Force $helloHex }
$savedBudget = $env:VIRE_BUDGET
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$r = Invoke-Bounded -Name "hello_host" -TimeoutSec 120 -FilePath "dotnet" -ArgumentList @(
    "exec", $VireDll, "--compiler", "compile-native.vire", "data/guest-hello.vire", "data/guest-hello.hex"
)
if ($r.StdOut -notmatch "compiled") { throw "hello_host missing compiled" }
Convert-HexToExe $helloHex $helloExe
$r = Invoke-Bounded -Name "hello_run" -TimeoutSec 15 -FilePath $helloExe -ArgumentList @()
if ($r.StdOut.Trim() -ne "hello from stage") { throw "hello_run stdout $($r.StdOut)" }
Write-Output "step_hello_pe ok"

$gen1Hex = Join-Path $Data "gen1.hex"
$gen1Exe = Join-Path $Data "gen1.exe"
if (Test-Path $gen1Hex) { Remove-Item -Force $gen1Hex }
$r = Invoke-Bounded -Name "gen1_host" -TimeoutSec 1800 -FilePath "dotnet" -ArgumentList @(
    "exec", $VireDll, "--compiler", "compile-native.vire", "data/compile-native.vire", "data/gen1.hex"
)
if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
if ($r.StdOut -notmatch "compiled") { throw "gen1_host missing compiled" }
Convert-HexToExe $gen1Hex $gen1Exe
Write-Output ("gen1_exe_bytes " + (Get-Item $gen1Exe).Length)
try { Unblock-File -Path $gen1Exe } catch { }
Start-Sleep -Seconds 2
try {
    Invoke-Bounded -Name "gen1_probe" -TimeoutSec 15 -FilePath $gen1Exe -ArgumentList @()
} catch {
    Write-Output ("gen1_probe_err " + $_.Exception.Message)
}
Write-Output "step_gen1_host ok"

$g1 = Join-Path $Root "g1.exe"
Copy-Item $gen1Exe $g1 -Force
$gen1HelloHex = Join-Path $Data "gen1-hello.hex"
$gen1HelloExe = Join-Path $Data "gen1-hello.exe"
if (Test-Path $gen1HelloHex) { Remove-Item -Force $gen1HelloHex }
$r = Invoke-Bounded -Name "gen1_hello" -TimeoutSec 120 -FilePath $g1 -ArgumentList @(
    "data/guest-hello.vire", "data/gen1-hello.hex"
)
if ($r.StdOut -notmatch "compiled") { throw "gen1_hello missing compiled" }
Convert-HexToExe $gen1HelloHex $gen1HelloExe
$r = Invoke-Bounded -Name "gen1_hello_run" -TimeoutSec 15 -FilePath $gen1HelloExe -ArgumentList @()
if ($r.StdOut.Trim() -ne "hello from stage") { throw "gen1_hello_run stdout $($r.StdOut)" }
Write-Output "step_gen1_hello ok"

$gen2Hex = Join-Path $Data "gen2.hex"
if (Test-Path $gen2Hex) { Remove-Item -Force $gen2Hex }
$r = Invoke-Bounded -Name "gen2_native" -TimeoutSec 2400 -FilePath $g1 -ArgumentList @(
    "data/compile-native.vire", "data/gen2.hex"
)
if ($r.StdOut -notmatch "compiled") { throw "gen2_native missing compiled" }
Write-Output ("gen1_hex_bytes " + (Get-Item $gen1Hex).Length)
Write-Output ("gen2_hex_bytes " + (Get-Item $gen2Hex).Length)
$h1 = (Get-FileHash -Algorithm SHA256 $gen1Hex).Hash.ToLowerInvariant()
$h2 = (Get-FileHash -Algorithm SHA256 $gen2Hex).Hash.ToLowerInvariant()
Write-Output "gen1_sha256 $h1"
Write-Output "gen2_sha256 $h2"
if ($h1 -ne $h2) {
    $a = [System.IO.File]::ReadAllBytes($gen1Hex)
    $b = [System.IO.File]::ReadAllBytes($gen2Hex)
    $n = [Math]::Min($a.Length, $b.Length)
    $i = 0
    while ($i -lt $n -and $a[$i] -eq $b[$i]) { $i++ }
    if ($i -lt $n) {
        $hi = [Math]::Min($n, $i + 16)
        $sliceA = ($a[$i..($hi - 1)] | ForEach-Object { $_.ToString("x2") }) -join ""
        $sliceB = ($b[$i..($hi - 1)] | ForEach-Object { $_.ToString("x2") }) -join ""
        Write-Output ("hex_mismatch_off $i gen1=$sliceA gen2=$sliceB")
    } else {
        Write-Output ("hex_mismatch_off $n prefix_equal lens $($a.Length) $($b.Length)")
    }
    throw "gen1/gen2 SHA-256 differ"
}
Write-Output "native selfhost handoff ok"
