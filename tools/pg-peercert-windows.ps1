# CouchStation: PE tls_peer_cert against VireProof pg-tls-stub (PLUS + MITM).
# Linux agents cannot execute PE. Caps stay 32MB / 100000 / 5M. Loopback only.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$AfterSha = (git rev-parse HEAD).Trim()
$FailBeforeSha = "880ec76172f9f2ab8d143566f89f1eb6d6d5daa7"
Write-Output "fail_before_sha $FailBeforeSha"
Write-Output "pass_after_sha $AfterSha"
Write-VireHostInfo

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

git cat-file -e "$FailBeforeSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { git fetch --depth 1 origin $FailBeforeSha }
$beforeTls = (& git -C $Root show "${FailBeforeSha}:src/rt-tls.vire") -join "`n"
if ($beforeTls -notmatch 'pin with labels, "rt_tls_peer_cert", image') { throw "FAIL_BEFORE missing peer-cert pin" }
if ($beforeTls -match "iat_fct") { throw "FAIL_BEFORE packed peer cert already present" }
Write-Output "FAIL_BEFORE at $FailBeforeSha PE tls_peer_cert is emitFail (packed SChannel blob has no leaf export)"

$OnWindows = ($env:OS -eq "Windows_NT")
if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
    if ($IsWindows) { $OnWindows = $true }
}

$ProofDll = Get-VireProofDll
$pfx = Join-Path $Data "pg-peercert.pfx"
$cer = Join-Path $Data "pg-peercert.pem"
$mitmPfx = Join-Path $Data "pg-peercert-mitm.pfx"
$mitmCer = Join-Path $Data "pg-peercert-mitm.pem"
& dotnet exec $ProofDll write-pfx $pfx $cer "x"
if ($LASTEXITCODE -ne 0) { throw "write-pfx honest failed" }
& dotnet exec $ProofDll write-pfx $mitmPfx $mitmCer "x"
if ($LASTEXITCODE -ne 0) { throw "write-pfx mitm failed" }

$lib = [IO.File]::ReadAllText((Join-Path $Root "src/rt-pg.vire"))
$utf8 = New-Object System.Text.UTF8Encoding $false

function Get-CerBytes([string]$CerPath) {
    $pem = [IO.File]::ReadAllText($CerPath)
    $b64 = (($pem -replace "-----BEGIN CERTIFICATE-----", "") -replace "-----END CERTIFICATE-----", "") -replace "\s", ""
    return [Convert]::FromBase64String($b64)
}

function Invoke-PeEndPoint([string]$Hash, [int]$Want) {
    $epPfx = Join-Path $Data ("pg-peercert-" + $Hash + ".pfx")
    $epCer = Join-Path $Data ("pg-peercert-" + $Hash + ".pem")
    & dotnet exec $ProofDll write-pfx $epPfx $epCer "x" $Hash
    if ($LASTEXITCODE -ne 0) { throw "write-pfx $Hash failed" }
    $der = Get-CerBytes $epCer
    $nums = ($der | ForEach-Object { $_.ToString() }) -join ", "
    $epGuest = @"
define main
  let xs be [$nums]
  let der be ""
  let i be 0
  while i < (length with xs)
    let der be der + (chr with (xs at i))
    let i be i + 1
  end
  let ep be tls_end_point with der
  say (length with ep)
end
"@
    $src = Join-Path $Data ("pg-peercert-ep-" + $Hash + ".vire")
    [IO.File]::WriteAllText($src, $epGuest, $utf8)
    Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    & dotnet exec $VireDll --compiler compile-native.vire ("data/pg-peercert-ep-" + $Hash + ".vire") ("data/pg-peercert-ep-" + $Hash + ".hex") pe
    if ($LASTEXITCODE -ne 0) { throw "PE compile ep-$Hash exit $LASTEXITCODE" }
    $env:VIRE_BUDGET = "5000000"
    Convert-HexToExe (Join-Path $Data ("pg-peercert-ep-" + $Hash + ".hex")) (Join-Path $Data ("pg-peercert-ep-" + $Hash + ".exe"))
    $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $Data ("pg-peercert-ep-" + $Hash + ".exe"))))
    if ($ascii -notmatch "CryptHashCertificate") { throw "PE ep-$Hash missing CryptHashCertificate" }
    Write-Output ("pe_endpoint_" + $Hash + "_compiled " + $Want)
    if (-not $OnWindows) { return }
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $out = & (Join-Path $Data ("pg-peercert-ep-" + $Hash + ".exe")) 2>&1 | Out-String } finally { $ErrorActionPreference = $savedEap }
    if ($LASTEXITCODE -ne 0) { throw "PE ep-$Hash exit $LASTEXITCODE out $out" }
    if ($out -notmatch [regex]::Escape("$Want")) { throw "PE ep-$Hash want $Want got $out" }
    Write-Output ("pe_endpoint_" + $Hash + "_ok " + $Want)
}

Invoke-PeEndPoint "sha384" 48
Invoke-PeEndPoint "sha512" 64

if (-not $OnWindows) {
    Write-Output "pe_execute_skipped linux agent cannot run PE; CouchStation must run this script"
    Write-Output "PASS_AFTER compile-only: packed blob pins rt_tls_end_point + iat_chc; PE SHA-384/512 guests compiled"
    Write-Output "pg_peercert_windows compile_ok"
    exit 0
}

function Invoke-PePg([int]$Port, [string]$CaRel, [string]$Tag) {
    $guest = @"
define main
  let opened be pg_open_ssl with "127.0.0.1", $Port, "user", "db", "pencil", "verify-full", "localhost", "$CaRel"
  if (opened at "ok") == true
    say "ok"
    say opened at "conn" at "auth"
  end
  if (opened at "ok") == false
    say opened at "why"
  end
end
"@
    $src = Join-Path $Data ("pg-peercert-" + $Tag + ".vire")
    [IO.File]::WriteAllText($src, ($lib + "`n" + $guest), $utf8)
    Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    & dotnet exec $VireDll --compiler compile-native.vire ("data/pg-peercert-" + $Tag + ".vire") ("data/pg-peercert-" + $Tag + ".hex") pe
    if ($LASTEXITCODE -ne 0) { throw "PE compile $Tag exit $LASTEXITCODE" }
    $env:VIRE_BUDGET = "5000000"
    Convert-HexToExe (Join-Path $Data ("pg-peercert-" + $Tag + ".hex")) (Join-Path $Data ("pg-peercert-" + $Tag + ".exe"))
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $out = & (Join-Path $Data ("pg-peercert-" + $Tag + ".exe")) 2>&1 | Out-String } finally { $ErrorActionPreference = $savedEap }
    return @{ Code = [int]$LASTEXITCODE; Out = "$out" }
}

$honestProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "pg-tls-stub", $pfx, "x", "honest") -WorkingDirectory $Root
try {
    $port = Get-ListenPort $honestProc
    Write-Output "pg_tls_stub_honest 127.0.0.1:$port"
    $r = Invoke-PePg $port "data/pg-peercert.pem" "honest"
    Write-Output $r.Out
    if ($r.Code -ne 0) { throw "honest PE exit $($r.Code)" }
    if ($r.Out -notmatch "ok") { throw "honest PE missing ok" }
    if ($r.Out -notmatch "scram-sha-256-plus") { throw "honest PE missing PLUS" }
    Write-Output "pe_plus_honest_ok"
} finally {
    try { if ($honestProc -and -not $honestProc.HasExited) { Stop-Process -Id $honestProc.Id -Force } } catch { }
}

$sha384Proc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "pg-tls-stub", (Join-Path $Data "pg-peercert-sha384.pfx"), "x", "honest") -WorkingDirectory $Root
try {
    $port = Get-ListenPort $sha384Proc
    Write-Output "pg_tls_stub_sha384 127.0.0.1:$port"
    $r = Invoke-PePg $port "data/pg-peercert-sha384.pem" "honest384"
    Write-Output $r.Out
    if ($r.Code -ne 0) { throw "sha384 PE exit $($r.Code)" }
    if ($r.Out -notmatch "ok") { throw "sha384 PE missing ok" }
    if ($r.Out -notmatch "scram-sha-256-plus") { throw "sha384 PE missing PLUS" }
    Write-Output "pe_plus_sha384_ok"
} finally {
    try { if ($sha384Proc -and -not $sha384Proc.HasExited) { Stop-Process -Id $sha384Proc.Id -Force } } catch { }
}

$sha512Proc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "pg-tls-stub", (Join-Path $Data "pg-peercert-sha512.pfx"), "x", "honest") -WorkingDirectory $Root
try {
    $port = Get-ListenPort $sha512Proc
    Write-Output "pg_tls_stub_sha512 127.0.0.1:$port"
    $r = Invoke-PePg $port "data/pg-peercert-sha512.pem" "honest512"
    Write-Output $r.Out
    if ($r.Code -ne 0) { throw "sha512 PE exit $($r.Code)" }
    if ($r.Out -notmatch "ok") { throw "sha512 PE missing ok" }
    if ($r.Out -notmatch "scram-sha-256-plus") { throw "sha512 PE missing PLUS" }
    Write-Output "pe_plus_sha512_ok"
} finally {
    try { if ($sha512Proc -and -not $sha512Proc.HasExited) { Stop-Process -Id $sha512Proc.Id -Force } } catch { }
}

$mitmProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "pg-tls-stub", $mitmPfx, "x", "mitm") -WorkingDirectory $Root
try {
    $port = Get-ListenPort $mitmProc
    Write-Output "pg_tls_stub_mitm 127.0.0.1:$port"
    $r = Invoke-PePg $port "data/pg-peercert.pem" "mitm"
    Write-Output $r.Out
    if ($r.Out -match "ok" -and $r.Out -match "scram-sha-256-plus") { throw "MITM cert must fail" }
    Write-Output "pe_mitm_cert_fail_closed"
} finally {
    try { if ($mitmProc -and -not $mitmProc.HasExited) { Stop-Process -Id $mitmProc.Id -Force } } catch { }
}

Write-Output "PASS_AFTER at $AfterSha PE tls_peer_cert PLUS vs pg-tls-stub; MITM cert fail-closed; PE tls_end_point SHA-384/512"
Write-Output "pg_peercert_windows pass"
