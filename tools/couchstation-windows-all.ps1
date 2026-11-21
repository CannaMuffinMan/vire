# One CouchStation session: every Windows PE proof the integration PRs request.
# Do not run on Linux. Do not touch Windows Defender. Do not reboot.
# Unsets VIRE_BUDGET first (inherited 5000000 fails BudgetCapTests).
# Never prints FCG_API_TOKEN. Loopback only. Caps stay 32MB / 100000 / 5M.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$Log = Join-Path $Data "couchstation-windows-all.log"
$Head = (git rev-parse HEAD).Trim()
$Stamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
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
    Log "BEGIN $Name sha $Head"
    try {
        & $Body
        Log "PASS $Name sha $Head"
    } catch {
        $script:fail = 1
        Log "FAIL $Name sha $Head err $($_.Exception.Message)"
    } finally {
        After-Child
    }
}
function Run-Script([string]$Rel) {
    $path = Join-Path $Root $Rel
    if (-not (Test-Path $path)) { throw "missing $Rel" }
    powershell -NoProfile -File $path
    if ($LASTEXITCODE -ne 0) { throw "$Rel exit $LASTEXITCODE" }
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

Run-Proof "dotnet-build" {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
    if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
}

Run-Proof "dotnet-test" {
    Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    dotnet test (Join-Path $Root "tests/Vire.Tests/Vire.Tests.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }
}

Run-Proof "native-selfhost-handoff" {
    $h = Join-Path $Root "tools/native-selfhost-handoff.ps1"
    if (Test-Path $h) { Run-Script "tools/native-selfhost-handoff.ps1" }
    else { Run-Script "tools/native-selfhost-proof.ps1" }
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
    & dotnet exec $VireDll --compiler compile-native.vire tests/fuzz/findings/native-pe-json-map.vire data/json-map.hex pe
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
    & dotnet exec $VireDll --compiler compile-native.vire tests/fuzz/findings/native-pe-parse-array.vire data/parse-array.hex pe
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

Run-Proof "session-prove-pe" {
    $src = Join-Path $Root "session-prove.vire"
    if (-not (Test-Path $src)) { throw "missing session-prove.vire" }
    $hex = Join-Path $Data "session-prove.hex"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    & dotnet exec $VireDll --compiler compile-native.vire $src data/session-prove.hex pe
    if ($LASTEXITCODE -ne 0) { throw "session-prove compile exit $LASTEXITCODE" }
    Convert-HexToExe $hex (Join-Path $Data "session-prove.exe")
    $peOut = & (Join-Path $Data "session-prove.exe") | Out-String
    $hostOut = & dotnet exec $VireDll $src | Out-String
    if ($peOut -ne $hostOut) { throw "session-prove host vs PE stdout mismatch" }
    Log "session_prove_host_native_match"
}

Log "summary_head $Head fail=$fail log=$Log"
if ($fail -ne 0) { exit 1 }
Write-Host "couchstation-windows-all ok. PE proof lives only on this Windows PC."
exit 0
