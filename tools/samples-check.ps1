# Runs each sample that can finish without a window or the network.
# Window and listen samples are skipped; a skip is not a pass.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"

$Dll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path -LiteralPath $Dll)) {
    Write-Output "building Release"
    & dotnet build -c Release --nologo
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
if (-not (Test-Path -LiteralPath $Dll)) {
    Write-Error "missing $Dll"
    exit 1
}

function Invoke-Vire([string]$Rel) {
    Write-Output "dotnet exec bin/Release/net10.0/vire.dll $Rel"
    $out = & dotnet exec $Dll $Rel 2>&1
    $script:LastCode = $LASTEXITCODE
    $script:LastLines = @($out | ForEach-Object { $_.ToString() })
    $script:LastLines | ForEach-Object { Write-Output $_ }
}

function Assert-Line([string]$Rel, [string]$Want, [bool]$ExpectFail) {
    $hit = $script:LastLines | Where-Object { $_ -eq $Want } | Select-Object -First 1
    if ($hit -ne $Want) {
        Write-Error "$Rel did not print '$Want'"
        exit 1
    }
    if ($ExpectFail) {
        if ($script:LastCode -eq 0) {
            Write-Error "$Rel should fail"
            exit 1
        }
        return
    }
    if ($script:LastCode -ne 0) {
        Write-Error "$Rel exited $($script:LastCode)"
        exit 1
    }
}

# These claim to run in GUIDE.md but do not finish headless.
Write-Output "skip work.vire: show waits on a window (desktop, or a terminal prompt); not headless"
Write-Output "skip board.vire: show waits on a window and a click; not headless"
Write-Output "skip serve.vire: listen binds a socket and does not exit"
Write-Output "skip optional/live.vire: fetch needs the public network"

$checks = @(
    @{ Rel = "samples/hello.vire"; Want = "hello from vire"; Fail = $false },
    @{ Rel = "samples/deps-demo.vire"; Want = "alpha beta hi 3 y"; Fail = $false },
    @{ Rel = "samples/deps-missing.vire"; Want = "vire: line 1 col 1: deps.lock does not name missingkit"; Fail = $true },
    @{ Rel = "count.vire"; Want = "5"; Fail = $false },
    @{ Rel = "term.vire"; Want = "hello from any machine"; Fail = $false },
    @{ Rel = "vault.vire"; Want = "vault written"; Fail = $false }
)

foreach ($check in $checks) {
    Invoke-Vire $check.Rel
    Assert-Line $check.Rel $check.Want ([bool]$check.Fail)
}

Write-Output "samples-check ok"
exit 0
