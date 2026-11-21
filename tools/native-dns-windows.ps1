# Fail-before / pass-after: native guest DNS stub on loopback UDP.
# CouchStation only. Caps unchanged. No external network.
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

$udp = New-Object System.Net.Sockets.UdpClient
$udp.Client.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, 0)))
$port = ([System.Net.IPEndPoint]$udp.Client.LocalEndPoint).Port
$worker = Start-Job -ScriptBlock {
    param($u)
    while ($true) {
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        try {
            $req = $u.Receive([ref]$ep)
            if ($req.Length -lt 12) { continue }
            $ans = New-Object byte[] ($req.Length + 16)
            [Array]::Copy($req, $ans, $req.Length)
            $ans[2] = 0x81
            $ans[3] = 0x80
            $ans[7] = 1
            $off = $req.Length
            $qoff = 12
            while ($qoff -lt $req.Length -and $req[$qoff] -ne 0) { $qoff += 1 + $req[$qoff] }
            $qoff += 1
            $qname = New-Object byte[] ($qoff - 12)
            [Array]::Copy($req, 12, $qname, 0, $qname.Length)
            $tail = $qname + [byte[]](0, 1, 0, 1, 0, 0, 0, 0, 0, 4, 127, 0, 0, 1)
            [Array]::Copy($tail, 0, $ans, $off, 16)
            $u.Send($ans, $ans.Length, $ep) | Out-Null
        } catch { break }
    }
} -ArgumentList $udp
Set-Content -Path (Join-Path $Data "vire-dns") -Value "127.0.0.1 $port`n" -NoNewline
$env:VIRE_DNS = "127.0.0.1:$port"
try {
    Copy-Item (Join-Path $Root "tests/native/dns-resolve.vire") (Join-Path $Data "dns-resolve.vire") -Force
    $code = Invoke-Vire "compile-native.vire" "data/dns-resolve.vire" "data/dns-resolve.hex"
    if ($code -ne 0) { throw "compile-native dns-resolve failed" }
    Convert-HexToExe (Join-Path $Data "dns-resolve.hex") (Join-Path $Data "dns-resolve.exe")
    $pe = & (Join-Path $Data "dns-resolve.exe")
    $hostOut = & dotnet exec $VireDll "data/dns-resolve.vire"
    Write-Output "host_out $hostOut"
    Write-Output "pe_out $pe"
    if ($pe -notmatch "127.0.0.1") { throw "PE missing 127.0.0.1" }
    if ($hostOut -notmatch "127.0.0.1") { throw "host missing 127.0.0.1" }
    Write-Output "PASS_AFTER native DNS loopback fixture"
} finally {
    try { $udp.Close() } catch { }
    try { Stop-Job $worker -ErrorAction SilentlyContinue } catch { }
}
