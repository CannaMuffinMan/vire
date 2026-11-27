# CouchStation PE proof for fcgcpa chain remainder (rotate / 507 / 503 / migrate / aliases / concurrent).
# Linux ELF proof is tools/rebuild-chain-limits-diff.sh. This script is the PE twin.
# Do not treat a Linux run as PE proof. Loopback 127.0.0.1 only. Caps unchanged.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$FailBefore = "5c3ed01abe2a12a34fca74b915d5e39a9f05fde3"
$After = (git rev-parse HEAD).Trim()
$Data = Join-Path $Root "data"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
$FixSrc = Join-Path $Root "data/rebuild/chain"
$FixDst = Join-Path $Root "data/chain"
$ProofDll = Get-VireProofDll
$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing data/gen1.exe; run native-selfhost-handoff.ps1 on Windows first" }
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

function Compile-Guest([string]$Src, [string]$Stem) {
    $vire = Get-Content -Raw -LiteralPath $Src
    $vire = $vire.Replace("listen with 18080", "listen with 0")
    $outSrc = Join-Path $Data "$Stem.vire"
    Set-Content -LiteralPath $outSrc -Value $vire -NoNewline
    $hex = Join-Path $Data "$Stem.hex"
    $exe = Join-Path $Data "$Stem.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    $p = Start-Process -FilePath $gen1 -ArgumentList @("data/$Stem.vire", "data/$Stem.hex") -WorkingDirectory $Root -NoNewWindow -PassThru
    $code = Get-ChildExitCode $p
    if ($code -ne 0) { throw "gen1 $Stem compile exit $code" }
    Convert-HexToExe $hex $exe
    return $exe
}

function Wait-Listen([string]$OutPath) {
    $until = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $until) {
        if (Test-Path $OutPath) {
            $text = Read-SharedText $OutPath
            if ($text -match "listening on 127.0.0.1:(\d+)") { return [int]$Matches[1] }
        }
        Start-Sleep -Milliseconds 50
    }
    throw "PE did not listen: $OutPath"
}

Write-Host "FAIL_BEFORE sha $FailBefore (PR #112 tip: GET /chain + bounded POST /block)"
Write-Host "PASS_AFTER sha $After"
Write-Host "caps stay arena 33554432 / list 100000 / steps 5000000"
Write-Host "CouchStation PE: compile fail-before-chain-remainder.vire then guest-chain.vire"

$failExe = Compile-Guest (Join-Path $Root "tests/rebuild/fail-before-chain-remainder.vire") "rebuild-chain-limits-fail-pe"
$failOut = Join-Path $Data "rebuild-chain-limits-fail-pe.out"
if (Test-Path $failOut) { Remove-Item -Force $failOut }
$fp = Start-Process -FilePath $failExe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput $failOut -PassThru
try {
    $fport = Wait-Listen $failOut
    Write-Host "fail_before_listen 127.0.0.1:$fport"
    & dotnet exec $ProofDll remainder-run "$fport" $FixSrc $FixDst fail-before
    if ($LASTEXITCODE -eq 0) { throw "FAIL_BEFORE expected remainder mismatch, got match" }
    if ($LASTEXITCODE -ne 2) { throw "FAIL_BEFORE harness error $LASTEXITCODE" }
} finally {
    Stop-Process -Id $fp.Id -Force -ErrorAction SilentlyContinue
}
Write-Host "FAIL_BEFORE at $FailBefore remainder mismatch as required"

$chainExe = Compile-Guest (Join-Path $Root "guest-chain.vire") "rebuild-chain-limits-pe"
$chainOut = Join-Path $Data "rebuild-chain-limits-pe.out"
if (Test-Path $chainOut) { Remove-Item -Force $chainOut }
$cp = Start-Process -FilePath $chainExe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput $chainOut -PassThru
try {
    $cport = Wait-Listen $chainOut
    Write-Host "native_pe_listen 127.0.0.1:$cport"
    & dotnet exec $ProofDll remainder-run "$cport" $FixSrc $FixDst pass-after
    if ($LASTEXITCODE -ne 0) { throw "PASS_AFTER PE remainder mismatch $LASTEXITCODE" }
} finally {
    Stop-Process -Id $cp.Id -Force -ErrorAction SilentlyContinue
}

$hostSrc = Join-Path $Root "rebuild-chain-limits-run.vire"
if (-not (Test-Path $hostSrc)) {
    $text = (Get-Content -Raw (Join-Path $Root "guest-chain.vire")).Replace("listen with 18080", "listen with 0")
    Set-Content -LiteralPath $hostSrc -Value $text -NoNewline
}
$hostOut = Join-Path $Data "rebuild-chain-limits-host.out"
if (Test-Path $hostOut) { Remove-Item -Force $hostOut }
$hp = Start-Process -FilePath "dotnet" -ArgumentList @("exec", $VireDll, $hostSrc) -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput $hostOut -PassThru
$chainOut2 = Join-Path $Data "rebuild-chain-limits-pe2.out"
if (Test-Path $chainOut2) { Remove-Item -Force $chainOut2 }
$cp2 = Start-Process -FilePath $chainExe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput $chainOut2 -PassThru
try {
    $hport = Wait-Listen $hostOut
    $nport = Wait-Listen $chainOut2
    Write-Host "pair host 127.0.0.1:$hport native PE 127.0.0.1:$nport"
    & dotnet exec $ProofDll remainder-pair "$hport" "$nport" $FixSrc $FixDst
    if ($LASTEXITCODE -ne 0) { throw "HOST_NATIVE PE remainder mismatch $LASTEXITCODE" }
} finally {
    Stop-Process -Id $hp.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $cp2.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS_AFTER at $After Windows PE host vs PE guest remainder (rotate/507/tamper/migrate/previousHash/concurrent)"
Write-Host "Windows PE rebuild-chain-limits steps completed on this CouchStation. Linux is not PE proof."
