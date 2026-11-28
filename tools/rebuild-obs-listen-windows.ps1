# Host-vs-native GET /obs 307 and listen GET/POST /proxy 200 on loopback.
# Linux ELF is not Windows PE proof.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
. (Join-Path $PSScriptRoot "native-loopback-proof.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
Write-Host "FAIL_BEFORE at 6693e0e5d78c9df775d0531a39a14a574239cfac: tools/rebuild-obs-listen-windows.ps1 stub exit 1"
Write-Host ("PASS_AFTER expect " + $AfterSha)
Assert-VireCaps $Root

$OnWindows = Test-VireOnWindows
$VireDll = Get-VireDll $Root
$Stage = Join-Path $Root "data/native-obs-listen"
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item (Join-Path $Root "src/dist-static.vire") (Join-Path $Stage "dist-static.vire") -Force
Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $Stage "http-client.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/fcgbds-dashboard-go.vire") (Join-Path $Stage "fcgbds-dashboard-go.vire") -Force
Copy-Item (Join-Path $Root "tests/native/proxy-reply.vire") (Join-Path $Stage "proxy-reply.vire") -Force

$dash = Join-Path $Stage $(if ($OnWindows) { "dash.exe" } else { "dash.elf" })
$proxy = Join-Path $Stage $(if ($OnWindows) { "proxy-reply.exe" } else { "proxy-reply.elf" })
try {
    if ($OnWindows) {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-obs-listen/fcgbds-dashboard-go.vire" -HexRel "data/native-obs-listen/dash.hex" -OutPath $dash -Pe
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-obs-listen/proxy-reply.vire" -HexRel "data/native-obs-listen/proxy-reply.hex" -OutPath $proxy -Pe
    } else {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-obs-listen/fcgbds-dashboard-go.vire" -HexRel "data/native-obs-listen/dash.hex" -OutPath $dash
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-obs-listen/proxy-reply.vire" -HexRel "data/native-obs-listen/proxy-reply.hex" -OutPath $proxy
    }

    $hostDash = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-obs-listen/fcgbds-dashboard-go.vire", "-") -WorkingDirectory $Root
    $hDash = Get-ListenPort $hostDash
    $natDash = Start-OwnedProcess -FilePath $dash -ArgumentList @("-") -WorkingDirectory $Root
    $nDash = Get-ListenPort $natDash
    [void](Compare-HostNativeHttp -HostPort $hDash -NatPort $nDash -Method "GET" -Path "/obs" -WantStatus 307 -WantContains '{"status":307}')
    Write-Host "HOST_NATIVE_MATCH GET /obs 307"
    Stop-OwnedProcessTree $hostDash.Id
    Stop-OwnedProcessTree $natDash.Id

    $ProofDll = Get-VireProofDll
    $upProc = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "http-upok") -WorkingDirectory $Root
    $upPort = Get-ListenPort $upProc
    Write-Host ("upstream 127.0.0.1:" + $upPort)
    $hostPx = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-obs-listen/proxy-reply.vire", "$upPort") -WorkingDirectory $Root
    $hPx = Get-ListenPort $hostPx
    $natPx = Start-OwnedProcess -FilePath $proxy -ArgumentList @("$upPort") -WorkingDirectory $Root
    $nPx = Get-ListenPort $natPx
    [void](Compare-HostNativeHttp -HostPort $hPx -NatPort $nPx -Method "GET" -Path "/proxy" -WantStatus 200 -WantContains "up-ok")
    [void](Compare-HostNativeHttp -HostPort $hPx -NatPort $nPx -Method "POST" -Path "/proxy" -Body "from-obs" -WantStatus 200 -WantContains "up-ok")
    Write-Host "HOST_NATIVE_MATCH listen GET/POST /proxy 200"
    Write-Host ("PASS_AFTER at " + $AfterSha)
} finally {
    Stop-AllOwnedTrees
}
exit 0
