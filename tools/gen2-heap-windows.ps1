# FAIL_BEFORE: gen2 crash at #71 head (3946d1c + security runtime).
# PASS_AFTER: this GC/emitExpr fix plus the same larger rt.vire/pe.vire.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$BaseSha = "3946d1c6c4f3fc12e4a486da600bba354ad60c64"
$BulkSha = "5ae87794c5672c14aedd02042af49e6cea278a81"
Write-Output "fail_before_sha $BaseSha"
Write-Output "bulk_sha $BulkSha"

function Invoke-Handoff([string]$Tree) {
    Push-Location -LiteralPath $Tree
    try {
        if (-not (Test-Path "bin/Release/net10.0/vire.dll")) {
            dotnet build vire.csproj -c Release | Out-Host
        }
        pwsh -File tools/native-selfhost-handoff.ps1
    } finally {
        Pop-Location
    }
}

git cat-file -t $BulkSha 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { git fetch origin $BaseSha $BulkSha 2>&1 | Out-Host }

$FailDir = Join-Path $Root "data/fail-before-gen2"
if (Test-Path $FailDir) { git worktree remove --force $FailDir 2>$null; Remove-Item -Recurse -Force $FailDir -ErrorAction SilentlyContinue }
git worktree add --detach $FailDir $BulkSha
$failHit = $false
$failOut = ""
try {
    Invoke-Handoff $FailDir
} catch {
    $failHit = $true
    $failOut = "$_"
    Write-Output $failOut
}
if (-not $failHit) { throw "FAIL_BEFORE expected gen2 crash at $BulkSha" }
Write-Output "FAIL_BEFORE at $BaseSha with bulk $BulkSha : gen2 crashed"

$PassDir = Join-Path $Root "data/pass-after-gen2"
if (Test-Path $PassDir) { git worktree remove --force $PassDir 2>$null; Remove-Item -Recurse -Force $PassDir -ErrorAction SilentlyContinue }
git worktree add --detach $PassDir HEAD
Push-Location $PassDir
try {
    git merge --no-edit $BulkSha
    if ($LASTEXITCODE -ne 0) { throw "PASS_AFTER merge of $BulkSha failed" }
    Invoke-Handoff $PassDir
} finally {
    Pop-Location
}
Write-Output "PASS_AFTER gen1=gen2 with bulk $BulkSha"
git worktree remove --force $FailDir
git worktree remove --force $PassDir
Write-Output "PASS_AFTER gen2 heap ok"
