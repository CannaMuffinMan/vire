# FAIL_BEFORE: old redis-prove-windows.ps1 skip path exited 0; current must not.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$Base = "103f189e54630f11a127907a84b91faa1b59375c"
$old = (git show "${Base}:tools/redis-prove-windows.ps1" | Out-String)
if ($LASTEXITCODE -ne 0) { throw "git show $Base redis-prove-windows.ps1 failed" }
if ($old.IndexOf("REDIS_SERVER_UNAVAILABLE") -lt 0) {
    throw "FAIL_BEFORE: $Base redis-prove-windows.ps1 missing REDIS_SERVER_UNAVAILABLE"
}
if ($old.IndexOf("exit 0") -lt 0) {
    throw "FAIL_BEFORE: $Base redis-prove-windows.ps1 missing exit 0"
}
$oldSkip = @'
$redis = $null
if ($null -eq $redis) {
    Write-Output "REDIS_SERVER_UNAVAILABLE on this Windows runner (no redis-server.exe / Memurai). Decode and adversarial fake-server proofs still ran. Live SET/GET against a real Redis binary was not executed here."
    Write-Output "redis windows prove ok (decode+adv; live redis residual)"
    exit 0
}
'@
& pwsh -NoProfile -Command $oldSkip
if ($LASTEXITCODE -ne 0) { throw "FAIL_BEFORE expected old skip path exit 0, got $LASTEXITCODE" }
Write-Output "FAIL_BEFORE skip path exit 0 at $Base"
& pwsh -File (Join-Path $PSScriptRoot "redis-prove-windows.ps1") -SkipPathSelfTest
if ($LASTEXITCODE -eq 0) { throw "new redis-prove-windows.ps1 must exit non-zero on skip path" }
Write-Output "PASS_AFTER skip path exit $LASTEXITCODE (fail closed)"
