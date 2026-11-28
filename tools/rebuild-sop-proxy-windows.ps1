# Host-vs-native landing SOP HMAC cookie + loopback proxy listen.
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
Write-Host "FAIL_BEFORE at 6693e0e5d78c9df775d0531a39a14a574239cfac: tools/rebuild-sop-proxy-windows.ps1 stub exit 1"
Write-Host ("PASS_AFTER expect " + $AfterSha)
Assert-VireCaps $Root

$OnWindows = Test-VireOnWindows
$VireDll = Get-VireDll $Root
$Stage = Join-Path $Root "data/native-sop-win"
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item (Join-Path $Root "src/http-client.vire") (Join-Path $Stage "http-client.vire") -Force
Copy-Item (Join-Path $Root "src/rt-crypto.vire") (Join-Path $Stage "rt-crypto.vire") -Force
Copy-Item (Join-Path $Root "src/sop-cookie.vire") (Join-Path $Stage "sop-cookie.vire") -Force
Copy-Item (Join-Path $Root "src/dist-static.vire") (Join-Path $Stage "dist-static.vire") -Force
Copy-Item (Join-Path $Root "src/portal-jwt.vire") (Join-Path $Stage "portal-jwt.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/landing-sop.vire") (Join-Path $Stage "landing-sop.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/landing-proxy.vire") (Join-Path $Stage "landing-proxy.vire") -Force

try {
    $fail = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "tests/rebuild/guests/sop-fail.vire") -WorkingDirectory $Root -Stage $Stage
    Write-Host $fail.Text
    if ($fail.Text -notmatch "not gated") { throw "fail-before missing not gated" }
    if ($fail.Text -notmatch "not proxied") { throw "fail-before missing not proxied" }
    Write-Host "FAIL_BEFORE sop-fail.vire"

    $sop = Join-Path $Stage $(if ($OnWindows) { "landing-sop.exe" } else { "landing-sop.elf" })
    $px = Join-Path $Stage $(if ($OnWindows) { "landing-proxy.exe" } else { "landing-proxy.elf" })
    if ($OnWindows) {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-sop-win/landing-sop.vire" -HexRel "data/native-sop-win/landing-sop.hex" -OutPath $sop -Pe
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-sop-win/landing-proxy.vire" -HexRel "data/native-sop-win/landing-proxy.hex" -OutPath $px -Pe
    } else {
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-sop-win/landing-sop.vire" -HexRel "data/native-sop-win/landing-sop.hex" -OutPath $sop
        Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/native-sop-win/landing-proxy.vire" -HexRel "data/native-sop-win/landing-proxy.hex" -OutPath $px
    }

    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $sb = New-Object byte[] 16
    $rng.GetBytes($sb)
    $secret = -join ($sb | ForEach-Object { $_.ToString("x2") })
    $NOW = "1000"
    $EXP_OK = "2000"

    function Cli-Pair([string]$Stem, [string]$Needle, [string[]]$SopArgs) {
        $h = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList (@("exec", $VireDll, "data/native-sop-win/landing-sop.vire") + $SopArgs) -WorkingDirectory $Root -Stage $Stage
        $n = Invoke-OwnedCli -FilePath $sop -ArgumentList $SopArgs -WorkingDirectory $Root -Stage $Stage
        if ($h.Text -ne $n.Text) { throw "HOST_NATIVE_MISMATCH sop $Stem" }
        if ($h.Text -notmatch $Needle) { throw "sop $Stem missing $Needle" }
        Write-Host ("HOST_NATIVE_MATCH sop " + $Stem)
        return $h.Text
    }

    $issued = Cli-Pair "issue" "v1\." @($secret, "0", $NOW, "issue", $EXP_OK)
    $cookie = ($issued -split "`n")[1].Trim()
    if (-not $cookie.StartsWith("v1.")) { throw "cookie missing v1. prefix" }
    [void](Cli-Pair "ok" "^ok" @($secret, "0", $NOW, "verify", $cookie, $NOW))
    [void](Cli-Pair "tamper" "tamper" @($secret, "0", $NOW, "verify", ($cookie + "00"), $NOW))
    [void](Cli-Pair "expired" "expired" @($secret, "0", $NOW, "verify", $cookie, "9000"))
    [void](Cli-Pair "missing" "missing" @($secret, "0", $NOW, "verify", "-", $NOW))
    $hdr = "Cookie:fcg_sop_authenticated=$cookie"
    [void](Cli-Pair "header" "^ok" @($secret, "0", $NOW, "header", $hdr, $NOW))

    $hostSop = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-sop-win/landing-sop.vire", $secret, "0", $NOW) -WorkingDirectory $Root
    $hSop = Get-ListenPort $hostSop
    $natSop = Start-OwnedProcess -FilePath $sop -ArgumentList @($secret, "0", $NOW) -WorkingDirectory $Root
    $nSop = Get-ListenPort $natSop
    Assert-HttpContract -Port $hSop -DocPath (Join-Path $Root "tests/rebuild/contracts/landing-go/sop-cookie.json") -Label "host"
    Assert-HttpContract -Port $nSop -DocPath (Join-Path $Root "tests/rebuild/contracts/landing-go/sop-cookie.json") -Label "native"
    [void](Compare-HostNativeHttp -HostPort $hSop -NatPort $nSop -Method "GET" -Path "/api/sop-auth" -Cookie ("fcg_sop_authenticated=" + $cookie) -WantStatus 200 -WantContains '{"ok":true}')
    [void](Compare-HostNativeHttp -HostPort $hSop -NatPort $nSop -Method "POST" -Path "/api/sop-auth" -Body $cookie -WantStatus 200)
    Write-Host "HOST_NATIVE_MATCH landing SOP listen"
    Stop-OwnedProcessTree $hostSop.Id
    Stop-OwnedProcessTree $natSop.Id

    $ProofDll = Get-VireProofDll
    $upProc = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "http-upok") -WorkingDirectory $Root
    $upPort = Get-ListenPort $upProc
    $hostPx = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-sop-win/landing-proxy.vire", "$upPort", "listen") -WorkingDirectory $Root
    $hPx = Get-ListenPort $hostPx
    $natPx = Start-OwnedProcess -FilePath $px -ArgumentList @("$upPort", "listen") -WorkingDirectory $Root
    $nPx = Get-ListenPort $natPx
    Assert-HttpContract -Port $hPx -DocPath (Join-Path $Root "tests/rebuild/contracts/landing-go/sop-proxy.json") -Label "host-proxy"
    Assert-HttpContract -Port $nPx -DocPath (Join-Path $Root "tests/rebuild/contracts/landing-go/sop-proxy.json") -Label "native-proxy"
    $hEcho = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-sop-win/landing-proxy.vire", "$upPort", "proxy-echo") -WorkingDirectory $Root -Stage $Stage
    $nEcho = Invoke-OwnedCli -FilePath $px -ArgumentList @("$upPort", "proxy-echo") -WorkingDirectory $Root -Stage $Stage
    if ($hEcho.Text -ne $nEcho.Text) { throw "HOST_NATIVE_MISMATCH proxy-echo" }
    if ($nEcho.Text -notmatch "up-ok") { throw "proxy-echo missing up-ok" }
    $hDown = Invoke-OwnedCli -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/native-sop-win/landing-proxy.vire", "$upPort", "proxy-down") -WorkingDirectory $Root -Stage $Stage
    $nDown = Invoke-OwnedCli -FilePath $px -ArgumentList @("$upPort", "proxy-down") -WorkingDirectory $Root -Stage $Stage
    if ($hDown.Text -ne $nDown.Text) { throw "HOST_NATIVE_MISMATCH proxy-down" }
    if ($nDown.Text -notmatch "502") { throw "proxy-down missing 502" }
    Write-Host "HOST_NATIVE_MATCH landing proxy"
    Write-Host ("PASS_AFTER at " + $AfterSha)
} finally {
    Stop-AllOwnedTrees
}
exit 0
