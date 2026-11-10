# Exact local GrokBuild handoff. Parent posts this. Do not run from a cloud Linux agent.
# Isolated checkout of 3d9fc58c80629f1fd6ac11b3576831f5c869087d. Caps unchanged.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
Write-Output ("DOTNET_CONFIGURATION hint: use Release dll only. Debug is not this recipe.")
Write-Output ("pwd " + $Root)
pwsh -File (Join-Path $PSScriptRoot "native-host-info.ps1")
$dll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $dll)) { throw "build Release first: dotnet build vire.csproj -c Release" }

function Time-Exec([string]$Name, [string[]]$Args, [int]$TimeoutSec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath "dotnet" -ArgumentList $Args -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $Root ("data/perf-" + $Name + ".out.txt")) -RedirectStandardError (Join-Path $Root ("data/perf-" + $Name + ".err.txt"))
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill($true) } catch { }
        throw "$Name timed out after $TimeoutSec s last err in data/perf-$Name.err.txt"
    }
    $sw.Stop()
    Write-Output ("phase_" + $Name + "_sec " + $sw.Elapsed.TotalSeconds.ToString("0.000") + " exit " + $p.ExitCode)
    Get-Content -Raw (Join-Path $Root ("data/perf-" + $Name + ".err.txt")) | Select-String -Pattern "total_steps|still running steps=" | Select-Object -Last 6
}

Time-Exec "hello" @("exec", $dll, "compile-native.vire", "guest-hello.vire", "data/guest-hello.hex") 120
Time-Exec "hexof" @("exec", $dll, "probe-hexof.vire") 60
Time-Exec "hexbuiltin" @("exec", $dll, "probe-hex-builtin.vire") 60
Time-Exec "openimage" @("exec", $dll, "probe-open-image.vire") 60
Time-Exec "emitu8" @("exec", $dll, "probe-emitu8.vire") 60
Write-Output "Keep stderr files. Compare hello wall to CI 5.6-7.1s on 7c7c8ea/3d9fc58. Do not raise 420s."
