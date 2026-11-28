# Compile rpc/dev/dashboard guests to native and match Linux portal contracts.
# Linux ELF is not Windows PE proof.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
. (Join-Path $PSScriptRoot "native-loopback-proof.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:JWT_SECRET -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
Write-Host "FAIL_BEFORE at 6693e0e5d78c9df775d0531a39a14a574239cfac: tools/rebuild-portal-windows.ps1 stub exit 1"
Write-Host ("PASS_AFTER expect " + $AfterSha)
Assert-VireCaps $Root

$OnWindows = Test-VireOnWindows
$VireDll = Get-VireDll $Root
$Stage = Join-Path $Root "data/native-portal-win"
$Dist = Join-Path $Root "data/rebuild-dist"
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $Stage "http-client.vire") -Force
Copy-Item (Join-Path $Root "src/rt-crypto.vire") (Join-Path $Stage "rt-crypto.vire") -Force
Copy-Item (Join-Path $Root "src/dist-static.vire") (Join-Path $Stage "dist-static.vire") -Force
Copy-Item (Join-Path $Root "src/portal-jwt.vire") (Join-Path $Stage "portal-jwt.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/portal-fail.vire") (Join-Path $Stage "portal-fail.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/rpc-portal-go.vire") (Join-Path $Stage "rpc-portal-go.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/dev-portal-go.vire") (Join-Path $Stage "dev-portal-go.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/fcgbds-dashboard-go.vire") (Join-Path $Stage "fcgbds-dashboard-go.vire") -Force
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "data") | Out-Null
if (Test-Path (Join-Path $Stage "data/rebuild-dist")) { Remove-Item -Recurse -Force (Join-Path $Stage "data/rebuild-dist") }
Copy-Item $Dist (Join-Path $Stage "data/rebuild-dist") -Recurse -Force

function Compile-Portal([string]$Stem) {
    $out = Join-Path $Stage ($Stem + $(if ($OnWindows) { ".exe" } else { ".elf" }))
    $rel = "data/native-portal-win/" + $Stem + ".vire"
    $hex = "data/native-portal-win/" + $Stem + ".hex"
    if ($OnWindows) {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel $rel -HexRel $hex -OutPath $out -Pe
    } else {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel $rel -HexRel $hex -OutPath $out
    }
    return $out
}

try {
    $failPath = Compile-Portal "portal-fail"
    $failProc = Start-OwnedProcess -FilePath $failPath -ArgumentList @() -WorkingDirectory $Root
    $fport = Get-ListenPort $failProc
    $mismatch = $false
    try {
        Assert-HttpContract -Port $fport -DocPath (Join-Path $Root "tests/rebuild/contracts/fcgbds-dashboard-go.json") -Label "portal-fail"
    } catch {
        $mismatch = $true
        Write-Host ("FAIL_BEFORE portal-fail vs dashboard: " + $_.Exception.Message)
    }
    Stop-OwnedProcessTree $failProc.Id
    if (-not $mismatch) { throw "FAIL_BEFORE expected mismatch" }

    $dash = Compile-Portal "fcgbds-dashboard-go"
    $rpc = Compile-Portal "rpc-portal-go"
    $dev = Compile-Portal "dev-portal-go"

    $hostDash = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-portal-win/fcgbds-dashboard-go.vire", "-") -WorkingDirectory $Root
    $hDash = Get-ListenPort $hostDash
    $natDash = Start-OwnedProcess -FilePath $dash -ArgumentList @("-") -WorkingDirectory $Root
    $nDash = Get-ListenPort $natDash
    Assert-HttpContract -Port $hDash -DocPath (Join-Path $Root "tests/rebuild/contracts/fcgbds-dashboard-go.json") -Label "host-dash"
    Assert-HttpContract -Port $nDash -DocPath (Join-Path $Root "tests/rebuild/contracts/fcgbds-dashboard-go.json") -Label "native-dash"
    Write-Host "HOST_NATIVE_MATCH dashboard contract"
    Stop-OwnedProcessTree $hostDash.Id
    Stop-OwnedProcessTree $natDash.Id

    $hostSt = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-portal-win/fcgbds-dashboard-go.vire", "data/rebuild-dist") -WorkingDirectory $Root
    $hSt = Get-ListenPort $hostSt
    $natSt = Start-OwnedProcess -FilePath $dash -ArgumentList @("data/rebuild-dist") -WorkingDirectory $Root
    $nSt = Get-ListenPort $natSt
    [void](Compare-HostNativeHttp -HostPort $hSt -NatPort $nSt -Method "GET" -Path "/" -WantStatus 200 -WantContains "portal-index")
    [void](Compare-HostNativeHttp -HostPort $hSt -NatPort $nSt -Method "GET" -Path "/about" -WantStatus 200 -WantContains "portal-about")
    Write-Host "HOST_NATIVE_MATCH dashboard static"
    Stop-OwnedProcessTree $hostSt.Id
    Stop-OwnedProcessTree $natSt.Id

    $NOW = "1000"
    $hostRpc = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-portal-win/rpc-portal-go.vire", "9", "listen", "-", $NOW, "-", "-") -WorkingDirectory $Root
    $hRpc = Get-ListenPort $hostRpc
    $natRpc = Start-OwnedProcess -FilePath $rpc -ArgumentList @("9", "listen", "-", $NOW, "-", "-") -WorkingDirectory $Root
    $nRpc = Get-ListenPort $natRpc
    Assert-HttpContract -Port $hRpc -DocPath (Join-Path $Root "tests/rebuild/contracts/rpc-portal-go.json") -Label "host-rpc"
    Assert-HttpContract -Port $nRpc -DocPath (Join-Path $Root "tests/rebuild/contracts/rpc-portal-go.json") -Label "native-rpc"
    Write-Host "HOST_NATIVE_MATCH rpc-portal-go contract"
    Stop-OwnedProcessTree $hostRpc.Id
    Stop-OwnedProcessTree $natRpc.Id

    $SECRET = "fixture-jwt-secret"
    $RPC_PAY = '{"role":"dev","exp":2000}'
    $hJwt = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-portal-win/rpc-portal-go.vire", "9", "jwt-sign", $SECRET, $NOW, "-", "-", "-", $RPC_PAY) -WorkingDirectory $Root -Stage $Stage
    $nJwt = Invoke-OwnedCli -FilePath $rpc -ArgumentList @("9", "jwt-sign", $SECRET, $NOW, "-", "-", "-", $RPC_PAY) -WorkingDirectory $Root -Stage $Stage
    if ($hJwt.Text -ne $nJwt.Text) { throw "HOST_NATIVE_MISMATCH jwt-sign" }
    $tok = ($hJwt.Text -split "`n")[1].Trim()
    if (-not $tok) { throw "missing jwt" }
    $hostOk = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-portal-win/rpc-portal-go.vire", "9", "listen", $SECRET, $NOW, "-", "-") -WorkingDirectory $Root
    $hOk = Get-ListenPort $hostOk
    $natOk = Start-OwnedProcess -FilePath $rpc -ArgumentList @("9", "listen", $SECRET, $NOW, "-", "-") -WorkingDirectory $Root
    $nOk = Get-ListenPort $natOk
    [void](Compare-HostNativeHttp -HostPort $hOk -NatPort $nOk -Method "GET" -Path "/api/dev/auth" -Cookie ("dev_session=" + $tok) -WantStatus 200 -WantContains '{"ok":true}')
    Write-Host "HOST_NATIVE_MATCH rpc JWT cookie gate"
    Stop-OwnedProcessTree $hostOk.Id
    Stop-OwnedProcessTree $natOk.Id

    $hostDev = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-portal-win/dev-portal-go.vire", "9", "listen", "-", $NOW, "-", "-") -WorkingDirectory $Root
    $hDev = Get-ListenPort $hostDev
    $natDev = Start-OwnedProcess -FilePath $dev -ArgumentList @("9", "listen", "-", $NOW, "-", "-") -WorkingDirectory $Root
    $nDev = Get-ListenPort $natDev
    Assert-HttpContract -Port $hDev -DocPath (Join-Path $Root "tests/rebuild/contracts/dev-portal-go-auth.json") -Label "host-dev"
    Assert-HttpContract -Port $nDev -DocPath (Join-Path $Root "tests/rebuild/contracts/dev-portal-go-auth.json") -Label "native-dev"
    $h405 = Invoke-LoopHttp -Port $hDev -Method "POST" -Path "/login"
    $n405 = Invoke-LoopHttp -Port $nDev -Method "POST" -Path "/login"
    if ($h405.Status -ne 405 -or $n405.Status -ne 405 -or $h405.Body -ne $n405.Body) { throw "dev 405 mismatch" }
    Write-Host "HOST_NATIVE_MATCH dev-portal 307/405"
    Stop-OwnedProcessTree $hostDev.Id
    Stop-OwnedProcessTree $natDev.Id

    Write-Host ("PASS_AFTER at " + $AfterSha)
} finally {
    Stop-AllOwnedTrees
}
exit 0
