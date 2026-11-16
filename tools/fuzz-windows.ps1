# Bounded Windows native PE fuzz. Real windows-latest runner, not Unicorn.
# Time budget is small so nightly does not block PR CI (this workflow is
# schedule / workflow_dispatch only).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_HEADLESS = "1"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$Work = Join-Path $Root "data/fuzz-windows"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Findings = Join-Path $Root "tests/fuzz/findings"
New-Item -ItemType Directory -Force -Path $Findings | Out-Null

function Convert-HexToExe([string]$hexPath, [string]$exePath) {
    $hex = [System.IO.File]::ReadAllText($hexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($exePath, $bytes)
}

$seeds = @(
    (Join-Path $Root "tests/native/hello-stage.vire"),
    (Join-Path $Root "tests/fuzz/corpus/hello.vire"),
    (Join-Path $Root "tests/fuzz/corpus/grammar-lists.vire"),
    (Join-Path $Root "guest-hello.vire")
)
$n = 4
if ($env:VIRE_FUZZ_NATIVE_ITERS) { $n = [int]$env:VIRE_FUZZ_NATIVE_ITERS }
if ($n -gt 8) { $n = 8 }
$budgetSec = 180
if ($env:VIRE_FUZZ_NATIVE_SECONDS) { $budgetSec = [int]$env:VIRE_FUZZ_NATIVE_SECONDS }
$sw = [Diagnostics.Stopwatch]::StartNew()
$ok = 0
$fault = 0
for ($i = 0; $i -lt $n; $i++) {
    if ($sw.Elapsed.TotalSeconds -gt $budgetSec) {
        Write-Output "windows pe fuzz time budget ${budgetSec}s reached after $i"
        break
    }
    $src = $seeds[$i % $seeds.Length]
    $guest = Join-Path $Work ("g$i.vire")
    $body = Get-Content -Raw -LiteralPath $src
    $body = "~ fuzz-windows $i`r`n" + $body
    Set-Content -LiteralPath $guest -Value $body -NoNewline
    $rel = "data/fuzz-windows/g$i.vire"
    $hexRel = "data/fuzz-windows/g$i.hex"
    Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    $outFile = Join-Path $Work "g$i.compile.out"
    $errFile = Join-Path $Work "g$i.compile.err"
    $p = Start-Process -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "--compiler", "compile-native.vire", $rel, $hexRel, "pe") -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $p.WaitForExit(120000)) {
        try { $p.Kill($true) } catch { }
        Write-Output "HANG compile g$i"
        Copy-Item $guest (Join-Path $Findings "native-win-hang-g$i.vire")
        $fault++
        continue
    }
    $stderr = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
    $stdout = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
    if ($stderr -match "internal error") {
        Write-Output "FINDING internal error compile g$i"
        Copy-Item $guest (Join-Path $Findings "native-win-internal-g$i.vire")
        $fault++
        continue
    }
    if ($p.ExitCode -ne 0) {
        Write-Output "compile g$i exit $($p.ExitCode) (fail-closed guest is ok)"
        continue
    }
    $exe = Join-Path $Work "g$i.exe"
    Convert-HexToExe (Join-Path $Root $hexRel) $exe
    $runOut = Join-Path $Work "g$i.run.out"
    $runErr = Join-Path $Work "g$i.run.err"
    $rp = Start-Process -FilePath $exe -WorkingDirectory $Work -NoNewWindow -PassThru -RedirectStandardOutput $runOut -RedirectStandardError $runErr
    if (-not $rp.WaitForExit(15000)) {
        try { $rp.Kill($true) } catch { }
        Write-Output "HANG run g$i"
        Copy-Item $guest (Join-Path $Findings "native-win-run-hang-g$i.vire")
        $fault++
        continue
    }
    if ($rp.ExitCode -eq -1073741819) {
        Write-Output "FINDING AV run g$i"
        Copy-Item $guest (Join-Path $Findings "native-win-av-g$i.vire")
        $fault++
        continue
    }
    Write-Output "windows pe g$i exit $($rp.ExitCode)"
    $ok++
}

# Path junction probe (host bind, not Defender).
$juncRoot = Join-Path $Work "junc"
New-Item -ItemType Directory -Force -Path (Join-Path $juncRoot "data") | Out-Null
$outside = Join-Path $Work "outside.txt"
Set-Content -LiteralPath $outside -Value "secret"
$junc = Join-Path $juncRoot "data\outlink"
cmd /c "mklink /J `"$junc`" `"$Work`"" | Out-Null
$probe = Join-Path $Root "data/fuzz-windows/junc-probe.vire"
@'
define main
  try
    say (read with "data/outlink/outside.txt")
  miss problem
    say problem
  end
end
'@ | Set-Content -LiteralPath $probe
$env:VIRE_BUDGET = "500000"
$jout = Join-Path $Work "junc.out"
$jerr = Join-Path $Work "junc.err"
Push-Location $juncRoot
try {
    $jp = Start-Process -FilePath "dotnet" -ArgumentList @("exec", $VireDll, (Join-Path $Work "junc-probe.vire")) -WorkingDirectory $juncRoot -NoNewWindow -PassThru -RedirectStandardOutput $jout -RedirectStandardError $jerr
    if (-not $jp.WaitForExit(15000)) { try { $jp.Kill($true) } catch { } }
} finally { Pop-Location }
$jtext = ((Get-Content -Raw $jout -ErrorAction SilentlyContinue) + (Get-Content -Raw $jerr -ErrorAction SilentlyContinue))
if ($jtext -match "secret") {
    Write-Output "FINDING junction escape"
    Copy-Item $probe (Join-Path $Findings "path-win-junction.vire")
    $fault++
} else {
    Write-Output "junction probe fail-closed"
}

Write-Output "windows pe fuzz ok=$ok faults=$fault seconds=$([int]$sw.Elapsed.TotalSeconds)"
# Nightly records faults as findings; do not fail the job on a security hit
# so the artifact/log is uploaded. PR CI does not run this script.
exit 0
