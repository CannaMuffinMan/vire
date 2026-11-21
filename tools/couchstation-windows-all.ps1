# One CouchStation session: every Windows PE proof the integration PRs request.
# Do not run on Linux. Do not touch Windows Defender. Do not reboot.
# Unsets VIRE_BUDGET first (inherited 5000000 fails BudgetCapTests).
# Never prints FCG_API_TOKEN. Loopback only. Caps stay 32MB / 100000 / 5M.
$ErrorActionPreference = "Stop"
$env:UseSharedCompilation = "false"
$env:MSBUILDDISABLENODEREUSE = "1"
$env:DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER = "1"
try { dotnet build-server shutdown | Out-Null } catch { }
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(exe|dll|pdb)$' } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
Remove-Item -ErrorAction SilentlyContinue -Force (Join-Path $Root "g1.exe")
$Log = Join-Path $Data "couchstation-windows-all.log"
$Head = (git rev-parse HEAD).Trim()
$Stamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
$Results = New-Object System.Collections.Generic.List[string]
$ExitCodes = New-Object System.Collections.Generic.List[string]
function Log([string]$msg) {
    $line = "$(Get-Date -Format o) $msg"
    Add-Content -LiteralPath $Log -Value $line
    Write-Host $line
}
Set-Content -LiteralPath $Log -Value "couchstation-windows-all start $Stamp"
Log "head_sha $Head"
Log "VIRE_BUDGET unset (do not export 5000000)"
Log "Defender: not touched. Reboot: not requested."
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
$fail = 0
function After-Child {
    Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
}
function Run-Proof([string]$Name, [scriptblock]$Body) {
    $script:CurrentProof = $Name
    $proofLog = Join-Path $Data ("couchstation-" + $Name + ".log")
    Set-Content -LiteralPath $proofLog -Value "BEGIN $Name sha $Head"
    Log "BEGIN $Name sha $Head log $proofLog"
    try {
        & $Body
        Log "PASS $Name sha $Head exit 0"
        $script:Results.Add("PASS $Name exit 0")
        $script:ExitCodes.Add("$Name 0")
        Add-Content -LiteralPath $proofLog -Value "PASS $Name sha $Head exit 0"
    } catch {
        $script:fail = 1
        $code = 1
        if ($_.Exception.Message -match "exit (\d+)") { $code = [int]$Matches[1] }
        if ($code -eq 0) { $code = 1 }
        Log "FAIL $Name sha $Head exit $code err $($_.Exception.Message)"
        $script:Results.Add("FAIL $Name exit $code")
        $script:ExitCodes.Add("$Name $code")
        Add-Content -LiteralPath $proofLog -Value ("FAIL exit $code " + $_.Exception.Message)
    } finally {
        After-Child
    }
}
function Require-Script([string]$Rel) {
    $path = Join-Path $Root $Rel
    if (-not (Test-Path $path)) { throw "missing required $Rel (must not skip)" }
}
function Stop-ProcessTree([int]$Id) {
    try { & taskkill.exe /PID $Id /T /F | Out-Null } catch { }
    try { Stop-Process -ErrorAction SilentlyContinue -Id $Id -Force } catch { }
}
function Run-Script([string]$Rel, [int]$TimeoutSec = 0) {
    $path = Join-Path $Root $Rel
    Require-Script $Rel
    if ($TimeoutSec -le 0) {
        if ($Rel -match "selfhost") { $TimeoutSec = 2400 } else { $TimeoutSec = 900 }
    }
    $outLog = Join-Path $Data ("couchstation-" + $script:CurrentProof + "-child.log")
    $errLog = $outLog + ".err"
    $p = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile","-File",$path) -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $null = $p.Handle
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        Stop-ProcessTree $p.Id
        throw "$Rel wall timeout ${TimeoutSec}s"
    }
    $p.WaitForExit()
    Get-Content -ErrorAction SilentlyContinue $outLog | ForEach-Object { Write-Host $_ }
    Get-Content -ErrorAction SilentlyContinue $errLog | ForEach-Object { Write-Host $_ }
    if (-not $p.HasExited) { throw "$Rel ERROR process still running after WaitForExit" }
    $codeObj = $p.ExitCode
    if ($null -eq $codeObj) { throw "$Rel ERROR unknown exit code" }
    $code = [int]$codeObj
    $combined = ""
    if (Test-Path -LiteralPath $outLog) { $combined += [IO.File]::ReadAllText($outLog) }
    if (Test-Path -LiteralPath $errLog) { $combined += "`n" + [IO.File]::ReadAllText($errLog) }
    if ($code -ne 0) { throw "$Rel exit $code" }
    if ($combined -notmatch "PASS_AFTER|HOST_NATIVE_MATCH|\bPASS\b") {
        throw "$Rel exit 0 missing PASS/FAIL marker"
    }
}

function Test-HarnessExitGuard {
    $probe = Join-Path $Data "harness-nopass.ps1"
    Set-Content -LiteralPath $probe -Value "Write-Host silent-ok`nexit 0"
    $p = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile","-File",$probe) -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $Data "harness-nopass.out") -RedirectStandardError (Join-Path $Data "harness-nopass.err")
    $null = $p.Handle
    if (-not $p.WaitForExit(15000)) { Stop-ProcessTree $p.Id; throw "harness probe wall timeout" }
    $p.WaitForExit()
    if ($null -eq $p.ExitCode) { throw "ERROR unknown exit code" }
    $text = ""
    if (Test-Path (Join-Path $Data "harness-nopass.out")) { $text = [IO.File]::ReadAllText((Join-Path $Data "harness-nopass.out")) }
    if ($p.ExitCode -eq 0 -and $text -notmatch "PASS_AFTER|HOST_NATIVE_MATCH|\bPASS\b") {
        Log "harness_guard: null-safe ExitCode=$($p.ExitCode); missing PASS marker treated as FAIL"
    } else {
        throw "harness guard expected missing PASS marker"
    }
    $caught = $false
    try { Run-Script "data/harness-nopass.ps1" } catch {
        if ("$($_.Exception.Message)" -match "missing PASS/FAIL marker") { $caught = $true } else { throw }
    }
    if (-not $caught) { throw "Run-Script must FAIL scripts that exit 0 with no PASS/FAIL marker" }
    Log "harness_exit_guard_ok Handle+WaitForExit+unknown-null+PASS marker"
}
function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

Run-Proof "harness-exit-guard" { Test-HarnessExitGuard }

Run-Proof "dotnet-build" {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
    if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
    dotnet build (Join-Path $Root "tools/VireProof/VireProof.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "vire-proof build failed" }
}

Run-Proof "dotnet-test" {
    Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    dotnet test (Join-Path $Root "tests/Vire.Tests/Vire.Tests.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }
}

Run-Proof "native-selfhost-handoff" {
    Require-Script "tools/native-selfhost-handoff.ps1"
    Run-Script "tools/native-selfhost-handoff.ps1"
}

Run-Proof "pe-selfhost-gen1-eq-gen2-x3" {
    $i = 0
    while ($i -lt 3) {
        $i = $i + 1
        Run-Script "tools/native-selfhost-proof.ps1"
        Log "selfhost_run $i sha $Head"
    }
}

Run-Proof "native-net-windows" { Run-Script "tools/native-net-windows.ps1" }
Run-Proof "rebuild-fcgcpa-windows" { Run-Script "tools/rebuild-fcgcpa-windows.ps1" }
Run-Proof "rebuild-fcgbds-worker-windows" { Run-Script "tools/rebuild-fcgbds-worker-windows.ps1" }
Run-Proof "json-prove-windows" { Run-Script "tools/json-prove-windows.ps1" }
Run-Proof "crypto-prove-windows" { Run-Script "tools/crypto-prove-windows.ps1" }
Run-Proof "pg-prove-windows" { Run-Script "tools/pg-prove-windows.ps1" }
Run-Proof "pg-tls-prove-windows" { Run-Script "tools/pg-tls-prove-windows.ps1" }
Run-Proof "fuzz-windows" { Run-Script "tools/fuzz-windows.ps1" }

Run-Proof "pe-json-map-fault-90" {
    $hex = Join-Path $Data "json-map.hex"
    $exe = Join-Path $Data "json-map.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    Copy-Item (Join-Path $Root "tests/fuzz/findings/native-pe-json-map.vire") (Join-Path $Data "json-map.vire") -Force
    & dotnet exec $VireDll --compiler compile-native.vire data/json-map.vire data/json-map.hex pe
    if ($LASTEXITCODE -ne 0) { throw "json-map compile exit $LASTEXITCODE" }
    Convert-HexToExe $hex $exe
    $out = & $exe
    $text = if ($null -eq $out) { "" } else { ($out | Out-String).Trim() }
    Log "pe_json_map_stdout $text"
    if ($text -notmatch '"a"') { throw "json-map PE stdout missing map; host expects {`"a`": 2}" }
}

Run-Proof "pe-parse-array-fault-90" {
    $hex = Join-Path $Data "parse-array.hex"
    $exe = Join-Path $Data "parse-array.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    Copy-Item (Join-Path $Root "tests/fuzz/findings/native-pe-parse-array.vire") (Join-Path $Data "parse-array.vire") -Force
    & dotnet exec $VireDll --compiler compile-native.vire data/parse-array.vire data/parse-array.hex pe
    if ($LASTEXITCODE -ne 0) { throw "parse-array compile exit $LASTEXITCODE" }
    Convert-HexToExe $hex $exe
    $code = 0
    & $exe
    $code = $LASTEXITCODE
    Log "pe_parse_array_exit $code"
    if ($code -ne 0) { throw "parse-array PE exit $code" }
}

Run-Proof "rebuild-proxy-windows-pe" {
    # tools/rebuild-proxy-windows.ps1 is a checklist (exits 1 until filled).
    # Compile the proxy guest to PE and record MZ + ws2_32 names.
    $src = Join-Path $Root "tests/rebuild/guests/proxy-http.vire"
    $stage = Join-Path $Data "proxy-pe"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-Item $src (Join-Path $stage "proxy-http.vire") -Force
    Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $stage "http-client.vire") -Force
    $hex = Join-Path $Data "proxy-http.hex"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    & dotnet exec $VireDll --compiler compile-native.vire data/proxy-pe/proxy-http.vire data/proxy-http.hex pe
    if ($LASTEXITCODE -ne 0) { throw "proxy compile exit $LASTEXITCODE" }
    Convert-HexToExe $hex (Join-Path $Data "proxy-http.exe")
    $pe = [System.IO.File]::ReadAllBytes((Join-Path $Data "proxy-http.exe"))
    if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "proxy PE missing MZ" }
    $ascii = [Text.Encoding]::ASCII.GetString($pe)
    if ($ascii -notmatch "ws2_32") { throw "proxy PE missing ws2_32" }
    Log "proxy_pe_mz_ok ws2_32_ok (host-vs-PE modes still need a loopback upstream on this PC)"
}

Run-Proof "native-json-parse-windows" { Run-Script "tools/native-json-parse-windows.ps1" }
Run-Proof "rebuild-sop-proxy-windows" { Run-Script "tools/rebuild-sop-proxy-windows.ps1" }
Run-Proof "rebuild-portal-windows" { Run-Script "tools/rebuild-portal-windows.ps1" }
Run-Proof "native-dns-windows" { Run-Script "tools/native-dns-windows.ps1" }
Run-Proof "rebuild-chain-limits-windows" { Run-Script "tools/rebuild-chain-limits-windows.ps1" }
Run-Proof "rebuild-fcgbds-heartbeat-windows" { Run-Script "tools/rebuild-fcgbds-heartbeat-windows.ps1" }
Run-Proof "redis-tls-prove-windows" { Run-Script "tools/redis-tls-prove-windows.ps1" }
Run-Proof "aes-gcm-windows" { Run-Script "tools/aes-gcm-windows.ps1" }
Run-Proof "rebuild-headers-windows" { Run-Script "tools/rebuild-headers-windows.ps1" }
Run-Proof "rebuild-obs-listen-windows" { Run-Script "tools/rebuild-obs-listen-windows.ps1" }
Run-Proof "rebuild-proxy-windows" { Run-Script "tools/rebuild-proxy-windows.ps1" }
Run-Proof "tls-server-windows" { Run-Script "tools/tls-server-windows.ps1" }
Run-Proof "pbkdf2-windows" { Run-Script "tools/pbkdf2-windows.ps1" }
Run-Proof "apigo-ws-windows" { Run-Script "tools/apigo-ws-windows.ps1" }
Run-Proof "rebuild-proxy-ws-windows" { Run-Script "tools/rebuild-proxy-ws-windows.ps1" }
Run-Proof "tls-schannel-windows" { Run-Script "tools/tls-schannel-windows.ps1" }
Run-Proof "pg-redis-tls-windows" { Run-Script "tools/pg-redis-tls-windows.ps1" }
Run-Proof "listen-ws-windows" { Run-Script "tools/listen-ws-windows.ps1" }
Run-Proof "ws-refuse-windows" { Run-Script "tools/ws-refuse-windows.ps1" }
Run-Proof "proxy-reply-windows" { Run-Script "tools/proxy-reply-windows.ps1" }

Run-Proof "session-prove-pe" {
    $src = Join-Path $Root "session-prove.vire"
    if (-not (Test-Path $src)) { throw "missing session-prove.vire" }
    Copy-Item $src (Join-Path $Data "session-prove.vire") -Force
    $hex = Join-Path $Data "session-prove.hex"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    & dotnet exec $VireDll --compiler compile-native.vire data/session-prove.vire data/session-prove.hex pe
    if ($LASTEXITCODE -ne 0) { throw "session-prove compile exit $LASTEXITCODE" }
    Convert-HexToExe $hex (Join-Path $Data "session-prove.exe")
    $peOut = & (Join-Path $Data "session-prove.exe") | Out-String
    $hostOut = & dotnet exec $VireDll $src | Out-String
    if ($peOut -ne $hostOut) { throw "session-prove host vs PE stdout mismatch" }
    Log "session_prove_host_native_match"
}

Log "summary_head $Head fail=$fail log=$Log"
Log "=== PASS/FAIL (every proof ran; none skipped) ==="
$i = 0
while ($i -lt $Results.Count) {
    Log $Results[$i]
    $i = $i + 1
}
Log "=== exit codes ==="
$i = 0
while ($i -lt $ExitCodes.Count) {
    Log ("exit " + $ExitCodes[$i])
    $i = $i + 1
}
if ($fail -ne 0) { exit 1 }
Write-Host "couchstation-windows-all ok. PE proof lives only on this Windows PC."
exit 0
