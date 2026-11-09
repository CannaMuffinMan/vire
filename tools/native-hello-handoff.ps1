# Time the LOCAL-CLI-HANDOFF host hello emit on Windows.
# Copies gitignored data/guest-hello.vire, feeds NUL stdin, bounds the wait.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $Root "guest-hello.vire") (Join-Path $Data "guest-hello.vire") -Force
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$outFile = Join-Path $Data "guest-hello.handoff.out.txt"
$errFile = Join-Path $Data "guest-hello.handoff.err.txt"
$inFile = Join-Path $Data "guest-hello.handoff.in.txt"
Set-Content -Path $inFile -Value "" -NoNewline
if (Test-Path $outFile) { Remove-Item -Force $outFile }
if (Test-Path $errFile) { Remove-Item -Force $errFile }
$hex = Join-Path $Data "guest-hello.hex"
if (Test-Path $hex) { Remove-Item -Force $hex }
$timeoutMs = 120000
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath "dotnet" -ArgumentList @(
    "exec", $VireDll, "compile-native.vire", "data/guest-hello.vire", "data/guest-hello.hex"
) -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
if (-not $p.WaitForExit($timeoutMs)) {
    try { $p.Kill($true) } catch { }
    $sw.Stop()
    throw "hello host compile timed out after $([int]$sw.Elapsed.TotalSeconds)s (limit 120s)"
}
$sw.Stop()
$stdout = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
$stderr = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
Write-Output "hello_host_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "hello_host_compile_exit $($p.ExitCode)"
if ($stderr) { Write-Output $stderr.TrimEnd() }
if ($stdout) { Write-Output $stdout.TrimEnd() }
if ($p.ExitCode -ne 0) { throw "hello host compile exit $($p.ExitCode)" }
if ($stdout -notmatch "compiled") { throw "hello host compile stdout missing compiled" }
if (-not (Test-Path $hex)) { throw "hello host compile wrote no hex" }
Write-Output "hello host compile ok"
