# Exact local GrokBuild handoff. Parent posts this. Do not run from a cloud Linux agent.
# Isolated checkout of 3d9fc58c80629f1fd6ac11b3576831f5c869087d. Caps unchanged.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $Root "guest-hello.vire") (Join-Path $Data "guest-hello.vire") -Force
Write-Output ("pwd " + $Root)
Write-VireHostInfo
$dll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $dll)) { throw "build Release first: dotnet build vire.csproj -c Release" }

function Time-Exec([string]$Name, [string[]]$Args, [int]$TimeoutSec) {
    $outFile = Join-Path $Data ("perf-" + $Name + ".out.txt")
    $errFile = Join-Path $Data ("perf-" + $Name + ".err.txt")
    $inFile = Join-Path $Data ("perf-" + $Name + ".in.txt")
    Set-Content -Path $inFile -Value "" -NoNewline
    if (Test-Path $outFile) { Remove-Item -Force $outFile }
    if (Test-Path $errFile) { Remove-Item -Force $errFile }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath "dotnet" -ArgumentList $Args -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill($true) } catch { }
        $sw.Stop()
        if (Test-Path $errFile) { Get-Content -Raw $errFile }
        throw "$Name timed out after $TimeoutSec s. Last stderr is $errFile"
    }
    $sw.Stop()
    Write-Output ("phase_" + $Name + "_sec " + $sw.Elapsed.TotalSeconds.ToString("0.000") + " exit " + $p.ExitCode)
    if (Test-Path $errFile) {
        Get-Content -Raw $errFile | Select-String -Pattern "total_steps|still running steps=" | Select-Object -Last 6
    }
    if ($p.ExitCode -ne 0) { throw "$Name exit $($p.ExitCode)" }
}

Time-Exec "hello" @("exec", $dll, "compile-native.vire", "data/guest-hello.vire", "data/guest-hello.hex") 120
Time-Exec "hexof" @("exec", $dll, "probe-hexof.vire") 60
Time-Exec "hexbuiltin" @("exec", $dll, "probe-hex-builtin.vire") 60
Time-Exec "openimage" @("exec", $dll, "probe-open-image.vire") 60
Time-Exec "emitu8" @("exec", $dll, "probe-emitu8.vire") 60
Write-Output "Keep data/perf-hello.err.txt. Compare phase_hello_sec to CI 5.619s (7c7c8ea) and 7.072s (3d9fc58). Do not raise 420s."
