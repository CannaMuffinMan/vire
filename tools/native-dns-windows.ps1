$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$BaseSha = "e236272cbf2355dbe79b13bc71d18f481da2e5b5"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $leaf = [IO.Path]::GetFileName($Args[0])
    $savedBudget = $env:VIRE_BUDGET
    if ($leaf -eq "compile-native.vire" -or $leaf -eq "compiler.vire") {
        $Args = @("--compiler") + $Args
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    }
    try {
        $out = & dotnet exec $VireDll @Args
        $code = $LASTEXITCODE
        if ($null -ne $out) { $out | Write-Host }
        if ($null -eq $code) { return 0 }
        return [int]$code
    } finally {
        if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
    }
}

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --depth 1 origin $BaseSha
}
$oldLines = @(& git -C $Root show "${BaseSha}:compile-native.vire")
$oldNative = ($oldLines | ForEach-Object { $_ }) -join "`n"
if ($oldNative -match 'nm == "resolve"') { throw "base compile-native already has resolve" }
Write-Output "FAIL_BEFORE at $BaseSha showing resolve is unavailable"

$ProofDll = Get-VireProofDll
$map = Join-Path $Data "vire-dns"
$dnsProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $ProofDll, "dns-stub", $map) -WorkingDirectory $Root
$until = (Get-Date).AddSeconds(8)
while ((Get-Date) -lt $until) {
    if ($dnsProc.HasExited) { throw "dns-stub exited $($dnsProc.ExitCode)" }
    if (Test-Path -LiteralPath $map) {
        $line = (Read-SharedText $map).Trim()
        if ($line -match "^127\.0\.0\.1 (\d+)$") { $port = [int]$Matches[1]; break }
    }
    Start-Sleep -Milliseconds 50
}
if (-not $port) { throw "dns-stub did not write map" }
$env:VIRE_DNS = "127.0.0.1:$port"
Write-Output "dns_stub $env:VIRE_DNS"
try {
    Copy-Item (Join-Path $Root "tests/native/dns-resolve.vire") (Join-Path $Data "dns-resolve.vire") -Force
    $code = Invoke-Vire "compile-native.vire" "data/dns-resolve.vire" "data/dns-resolve.hex"
    if ($code -ne 0) { throw "compile-native dns-resolve failed" }
    Convert-HexToExe (Join-Path $Data "dns-resolve.hex") (Join-Path $Data "dns-resolve.exe")
    $peBytes = [IO.File]::ReadAllBytes((Join-Path $Data "dns-resolve.exe"))
    $share7 = [byte[]](0x41, 0xb8, 7, 0, 0, 0)
    $pushRbx = [byte[]](0x53, 0x48, 0x89, 0x4d, 0xf8)
    $align88 = [byte[]](0x48, 0x81, 0xec, 0x88, 0, 0, 0, 0x53)
    function IndexOfBytes([byte[]]$hay, [byte[]]$needle) {
        for ($i = 0; $i -le $hay.Length - $needle.Length; $i++) {
            $ok = $true
            for ($j = 0; $j -lt $needle.Length; $j++) {
                if ($hay[$i + $j] -ne $needle[$j]) { $ok = $false; break }
            }
            if ($ok) { return $i }
        }
        return -1
    }
    if ((IndexOfBytes $peBytes $share7) -lt 0) { throw "FAIL_BEFORE PE DNS missing FILE_SHARE 7 (packed r4)" }
    if ((IndexOfBytes $peBytes $pushRbx) -lt 0) { throw "FAIL_BEFORE PE DNS missing push rbx in dns_hostok" }
    if ((IndexOfBytes $peBytes $align88) -lt 0) { throw "FAIL_BEFORE PE DNS rbx frame still sub rsp,0x80 (Win64 RSP misaligned at CreateFileA)" }
    $pe = & (Join-Path $Data "dns-resolve.exe")
    $hostOut = & dotnet exec $VireDll "data/dns-resolve.vire"
    Write-Output "host_out $hostOut"
    Write-Output "pe_out $pe"
    if ("$pe" -notmatch "127.0.0.1") { throw "PE missing 127.0.0.1" }
    if ("$hostOut" -notmatch "127.0.0.1") { throw "host missing 127.0.0.1" }
    Write-Output "PASS_AFTER native DNS loopback fixture"
} finally {
    try { if (-not $dnsProc.HasExited) { $dnsProc.Kill() } } catch { }
}
