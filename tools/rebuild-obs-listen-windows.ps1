# CouchStation PE: dashboard GET /obs 307 plus listen GET/POST /proxy 200.
# Linux ELF: tools/rebuild-portal-diff.sh + tools/proxy-reply-proof.sh.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Host "FAIL_BEFORE packed GET /proxy empty HTTP; dashboard /obs native wrap 500"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) {
    dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
$ProofDll = Get-VireProofDll

function Compile-Pe([string]$Src, [string]$Stem, [string[]]$Beside) {
    $dir = Join-Path $Root "data/$Stem"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item $Src (Join-Path $dir "$Stem.vire") -Force
    foreach ($b in $Beside) {
        Copy-Item (Join-Path $Root $b) (Join-Path $dir (Split-Path $b -Leaf)) -Force
    }
    $hex = Join-Path $dir "$Stem.hex"
    $exe = Join-Path $dir "$Stem.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    & dotnet exec $VireDll --compiler compile-native.vire "data/$Stem/$Stem.vire" "data/$Stem/$Stem.hex" pe
    if ($LASTEXITCODE -ne 0) { throw "compile $Stem exit $LASTEXITCODE" }
    $hexText = (Get-Content -Raw $hex).Trim()
    $pe = New-Object byte[] ($hexText.Length / 2)
    for ($i = 0; $i -lt $pe.Length; $i++) { $pe[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16) }
    [IO.File]::WriteAllBytes($exe, $pe)
    return $exe
}

$dashExe = Compile-Pe (Join-Path $Root "tests/rebuild/guests/fcgbds-dashboard-go.vire") "obs-dash-pe" @("src/dist-static.vire")
$dashHost = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/obs-dash-pe/obs-dash-pe.vire", "-") -WorkingDirectory $Root
$dashPe = Start-VireProcess -FilePath $dashExe -ArgumentList @("-") -WorkingDirectory $Root
try {
    $hp = Get-ListenPort $dashHost
    $np = Get-ListenPort $dashPe
    $h = Invoke-VireHttpRequest -Port $hp -Method "GET" -Path "/obs"
    $p = Invoke-VireHttpRequest -Port $np -Method "GET" -Path "/obs"
    if ($h.Status -ne 307 -or $p.Status -ne 307) { throw "obs status $($h.Status)/$($p.Status)" }
    if ($h.Body -ne $p.Body) { throw "obs body mismatch" }
    Write-Host "HOST_NATIVE_MATCH GET /obs 307"
} finally {
    try { $dashHost.Kill() } catch { }
    try { $dashPe.Kill() } catch { }
}

$up = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "http-upok") -WorkingDirectory $Root
$upPort = Get-ListenPort $up
$pxExe = Compile-Pe (Join-Path $Root "tests/native/proxy-reply.vire") "obs-proxy-pe" @("src/http-client.vire")
$pxHost = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/obs-proxy-pe/obs-proxy-pe.vire", "$upPort") -WorkingDirectory $Root
$pxPe = Start-VireProcess -FilePath $pxExe -ArgumentList @("$upPort") -WorkingDirectory $Root
try {
    $hp = Get-ListenPort $pxHost
    $np = Get-ListenPort $pxPe
    $hg = Invoke-VireHttpRequest -Port $hp -Method "GET" -Path "/proxy"
    $pg = Invoke-VireHttpRequest -Port $np -Method "GET" -Path "/proxy"
    $hpst = Invoke-VireHttpRequest -Port $hp -Method "POST" -Path "/proxy" -Send "from-listen"
    $ppst = Invoke-VireHttpRequest -Port $np -Method "POST" -Path "/proxy" -Send "from-listen"
    if ($hg.Status -ne 200 -or $pg.Status -ne 200 -or $hg.Body -notmatch "up-ok" -or $hg.Body -ne $pg.Body) { throw "GET /proxy mismatch" }
    if ($hpst.Status -ne 200 -or $ppst.Status -ne 200 -or $hpst.Body -ne $ppst.Body) { throw "POST /proxy mismatch" }
    Write-Host "HOST_NATIVE_MATCH listen GET/POST /proxy 200"
    Write-Host "PASS_AFTER at $AfterSha"
} finally {
    try { $pxHost.Kill() } catch { }
    try { $pxPe.Kill() } catch { }
    try { $up.Kill() } catch { }
}
Write-Host "rebuild-obs-listen-windows ok"
exit 0
