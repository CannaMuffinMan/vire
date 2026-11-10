$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
$Src = Join-Path $Data "src"
New-Item -ItemType Directory -Force -Path $Src | Out-Null
Copy-Item (Join-Path $Root "guest-hello.vire") (Join-Path $Data "guest-hello.vire") -Force
Write-VireHostInfo
try {
    $scheme = (powercfg /getactivescheme | Out-String).Trim()
    Write-Output ("power_plan " + ($scheme -replace '\s+', ' '))
} catch {
    Write-Output "power_plan unread"
}
$dll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $dll)) { throw "build Release first: dotnet build vire.csproj -c Release" }
$stampHelper = Join-Path $PSScriptRoot "perf-stamp-stderr.ps1"

function Invoke-Stamped {
    param(
        [string]$Name,
        [string[]]$ArgumentList,
        [int]$TimeoutSec
    )
    $outFile = Join-Path $Data ("perf-" + $Name + ".out.txt")
    $errFile = Join-Path $Data ("perf-" + $Name + ".err.txt")
    $inFile = Join-Path $Data ("perf-" + $Name + ".in.txt")
    $stampFile = Join-Path $Data ("perf-" + $Name + ".stamp.txt")
    Set-Content -Path $inFile -Value "" -NoNewline
    if (Test-Path $outFile) { Remove-Item -Force $outFile }
    if (Test-Path $errFile) { Remove-Item -Force $errFile }
    if (Test-Path $stampFile) { Remove-Item -Force $stampFile }
    New-Item -ItemType File -Path $errFile -Force | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath "dotnet" -ArgumentList $ArgumentList -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $stamper = Start-Process -FilePath "pwsh" -ArgumentList @("-NoProfile", "-File", $stampHelper, "-ErrPath", $errFile, "-StampPath", $stampFile, "-WatchPid", $p.Id) -WorkingDirectory $Root -NoNewWindow -PassThru
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill($true) } catch { }
        $sw.Stop()
        Start-Sleep -Milliseconds 200
        Write-Output ("phase_" + $Name + "_sec " + $sw.Elapsed.TotalSeconds.ToString("0.000") + " timeout 1")
        if (Test-Path $stampFile) { Write-Output (Get-Content -Raw $stampFile) }
        throw "$Name timed out after $TimeoutSec s. stamped stderr $stampFile"
    }
    $sw.Stop()
    try { Wait-Process -Id $stamper.Id -Timeout 15 } catch { }
    Write-Output ("phase_" + $Name + "_sec " + $sw.Elapsed.TotalSeconds.ToString("0.000") + " exit " + $p.ExitCode)
    if (Test-Path $stampFile) {
        $lines = Get-Content $stampFile | Where-Object { $_ -match "still running steps=|total_steps=" }
        $lines | Select-Object -First 3 | ForEach-Object { Write-Output $_ }
        $lines | Select-Object -Last 3 | ForEach-Object { Write-Output $_ }
        Write-Output ("stamp_lines " + ((Get-Content $stampFile | Measure-Object -Line).Lines))
    }
    if ($p.ExitCode -ne 0) { throw "$Name exit $($p.ExitCode)" }
}

Write-Output "break_miss_begin"
dotnet test (Join-Path $Root "tests/Vire.Tests/Vire.Tests.csproj") -c Release --nologo --filter FullyQualifiedName~PerfBreakMissCost
Write-Output "break_miss_end"

Invoke-Stamped -Name "hello" -TimeoutSec 120 -ArgumentList @("exec", $dll, "compile-native.vire", "data/guest-hello.vire", "data/guest-hello.hex")
Copy-Item (Join-Path $Root "compile-native.vire") (Join-Path $Data "compile-native.vire") -Force
Copy-Item (Join-Path $Root "src/asm.vire") (Join-Path $Src "asm.vire") -Force
Copy-Item (Join-Path $Root "src/pe.vire") (Join-Path $Src "pe.vire") -Force
Copy-Item (Join-Path $Root "src/rt.vire") (Join-Path $Src "rt.vire") -Force
Copy-Item (Join-Path $Root "src/rt-more.vire") (Join-Path $Src "rt-more.vire") -Force
Invoke-Stamped -Name "gen1host" -TimeoutSec 420 -ArgumentList @("exec", $dll, "compile-native.vire", "data/compile-native.vire", "data/gen1.hex")
Write-Output "profile_windows ok"
Write-Output "artifacts data/perf-hello.stamp.txt data/perf-gen1host.stamp.txt data/perf-hello.err.txt data/perf-gen1host.err.txt"
