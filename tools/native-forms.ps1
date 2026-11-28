# Host interpreter vs native try/miss and for-list.
# Tracked fixtures: data/native-forms/try-miss.vire and for-list.vire.
# Linux ELF is not Windows PE proof. CouchStation runs this script for PE.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
. (Join-Path $PSScriptRoot "native-loopback-proof.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
Write-Host "FAIL_BEFORE at 6693e0e5d78c9df775d0531a39a14a574239cfac: missing data/native-forms try-miss.vire and for-list.vire"
Write-Host ("PASS_AFTER expect " + $AfterSha)
Assert-VireCaps $Root

$OnWindows = Test-VireOnWindows
$Work = Join-Path $Root "data/native-forms"
if (-not (Test-Path (Join-Path $Work "try-miss.vire"))) { throw "missing data/native-forms/try-miss.vire" }
if (-not (Test-Path (Join-Path $Work "for-list.vire"))) { throw "missing data/native-forms/for-list.vire" }

$VireDll = Get-VireDll $Root
$failed = $false
try {
    foreach ($program in @("try-miss", "for-list")) {
        $srcRel = "data/native-forms/" + $program + ".vire"
        $hexRel = "data/native-forms/" + $program + ".hex"
        $outName = if ($OnWindows) { $program + ".exe" } else { $program + ".elf" }
        $outPath = Join-Path $Work $outName
        if ($OnWindows) {
            Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel $srcRel -HexRel $hexRel -OutPath $outPath -Pe
        } else {
            Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel $srcRel -HexRel $hexRel -OutPath $outPath
        }
        $hostRun = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList @("exec", $VireDll, $srcRel) -WorkingDirectory $Root -Stage $Work
        if ($hostRun.Code -ne 0) {
            Write-Host "FAIL interpret $program exit=$($hostRun.Code)"
            $failed = $true
            continue
        }
        $natRun = Invoke-OwnedCli -FilePath $outPath -ArgumentList @() -WorkingDirectory $Root -Stage $Work
        if ($hostRun.Text -ne $natRun.Text -or $natRun.Code -ne 0) {
            Write-Host "FAIL run $program host=$($hostRun.Text) native=$($natRun.Text) exit=$($natRun.Code)"
            $failed = $true
            continue
        }
        Write-Host "HOST_NATIVE_MATCH $program"
        Write-Host "PASS $program"
    }
} finally {
    Stop-AllOwnedTrees
}
if ($failed) { exit 1 }
Write-Host ("PASS_AFTER at " + $AfterSha)
Write-Host "native forms ok"
exit 0
