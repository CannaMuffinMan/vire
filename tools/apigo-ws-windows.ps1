# CouchStation Windows PE proof for api-go chat/live WS on native RFC 6455.
# Linux agent does not claim PE runtime. Caps must stay arena 32MB / list 100000 / steps 5M.
# GitHub Actions billing-lock is not a code failure.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_HEADLESS = "1"
$env:VIRE_BUDGET = "5000000"
$AfterSha = (git rev-parse HEAD).Trim()
$FailBefore = "2a64dbe9adea97751f59faa1543c1d7a0f2a215a"
Write-Output ("FAIL_BEFORE at " + $FailBefore + ": host listen had no RFC 6455 upgrade (VireListen answered JSON); native ELF already echoed")
Write-Output ("PASS_AFTER expect " + $AfterSha)

$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
Write-Output "caps_src_ok arena=33554432 list=100000 steps=5000000"

$VireDll = Join-Path $Root "bin\Release\net10.0\vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll — build Release first" }

$Data = Join-Path $Root "data\apigo-ws"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $Root "tests\rebuild\guests\apigo-ws.vire") (Join-Path $Data "apigo-ws.vire") -Force

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

Write-Output "TODO CouchStation:"
Write-Output "  1. dotnet exec vire.dll --compiler compile-native.vire data/apigo-ws/apigo-ws.vire data/apigo-ws/apigo-ws.hex"
Write-Output "  2. Convert hex to PE (MZ). Confirm Switching Protocols + 258EAFA5 GUID in image."
Write-Output "  3. Run PE; parse 'listening on 127.0.0.1:PORT'."
Write-Output "  4. Repeat host: dotnet exec vire.dll data/apigo-ws/apigo-ws.vire"
Write-Output "  5. For /ws/kick /ws/chat /ws/live /chat /live: GET Upgrade websocket v13 -> 101 + Accept."
Write-Output "  6. Masked text echo xyz; unmasked/RSV/frag ping close 1002; 64-bit tiny and 65537 close 1009."
Write-Output "  7. Do not raise caps. Do not change Defender. Loopback only."
Write-Output "Fill PASS_AFTER PE hashes here after the CouchStation run."
exit 1
