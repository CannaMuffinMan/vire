# CouchStation PE proof for listen Cookie/Host/Authorization + Set-Cookie/Location allowlist.
# Linux ELF is tools/rebuild-header-diff.sh plus rebuild-sop-proxy-diff.sh / rebuild-portal-diff.sh.
# This Linux VM does not claim PE proof.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing gen1.exe; run native-selfhost-handoff.ps1 first" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Compile-Guest([string]$Src, [string]$Stem) {
    $outSrc = Join-Path $Data "$Stem.vire"
    Copy-Item -LiteralPath $Src -Destination $outSrc -Force
    $hex = Join-Path $Data "$Stem.hex"
    $exe = Join-Path $Data "$Stem.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    $p = Start-Process -FilePath $gen1 -ArgumentList @("data/$Stem.vire", "data/$Stem.hex") -WorkingDirectory $Root -NoNewWindow -PassThru
    $code = Get-ChildExitCode $p
    if ($code -ne 0) { throw "gen1 $Stem compile exit $code" }
    Convert-HexToExe $hex $exe
    return $exe
}

function Read-Http([int]$Port, [string]$Path, [string]$Cookie) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("GET $Path HTTP/1.1`r`nHost: example.test`r`nConnection: close`r`n")
    if ($Cookie) { [void]$sb.Append("Cookie: $Cookie`r`n") }
    [void]$sb.Append("`r`n")
    $head = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $stream.Write($head, 0, $head.Length)
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 4096
    try {
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    } catch {
        if ($ms.Length -eq 0) { throw }
    }
    $tcp.Close()
    $text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    $split = $text.IndexOf("`r`n`r`n")
    $start = $text.Substring(0, $split)
    $body = $text.Substring($split + 4)
    $status = [int]($start.Split(" ")[1])
    return @{ Status = $status; Head = $start; Body = $body }
}

Write-Host "CouchStation PE: header-inject.vire allowlist + CRLF refusal"
$exe = Compile-Guest (Join-Path $Root "tests/rebuild/guests/header-inject.vire") "rebuild-headers-pe"
$proc = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput (Join-Path $Data "rebuild-headers-pe.out") -PassThru
Start-Sleep -Milliseconds 400
$out = Get-Content -Raw (Join-Path $Data "rebuild-headers-pe.out")
if ($out -notmatch "listening on 127.0.0.1:(\d+)") { Stop-Process -Id $proc.Id -Force; throw "headers PE did not listen" }
$port = [int]$Matches[1]
try {
    $echo = Read-Http $port "/echo-head" "a=1"
    if ($echo.Body -notmatch "Cookie: a=1") { throw "PE echo missing Cookie" }
    if ($echo.Body -match "X-Evil") { throw "PE leaked extra request header" }
    $ok = Read-Http $port "/set-ok" $null
    if ($ok.Status -ne 200) { throw "PE set-ok $($ok.Status)" }
    if ($ok.Head -notmatch "Set-Cookie: sid=safe") { throw "PE missing Set-Cookie" }
    if ($ok.Head -notmatch "Location: /next") { throw "PE missing Location" }
    $bad = Read-Http $port "/inject-location" $null
    if ($bad.Status -ne 500) { throw "PE inject-location expected 500 got $($bad.Status)" }
    if ($bad.Head -match "stolen=1") { throw "PE CRLF Location escaped" }
    $bad2 = Read-Http $port "/inject-cookie" $null
    if ($bad2.Status -ne 500) { throw "PE inject-cookie expected 500 got $($bad2.Status)" }
    if ($bad2.Head -match "Location: /evil") { throw "PE CRLF Set-Cookie escaped" }
    Write-Host "PASS_AFTER PE header allowlist + CRLF refusal match"
} finally {
    Stop-Process -Id $proc.Id -Force
}
Write-Host "Also re-run tools/rebuild-sop-proxy-windows.ps1 and tools/rebuild-portal-windows.ps1 after this lane."
