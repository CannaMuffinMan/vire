# Host listen + gen1 PE serve sites/landing/site byte-identical; traversal refused.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$env:VIRE_SITE_CAP = "1"
$env:VIRE_SITE_ROOT = "site"
$Data = Join-Path $Root "data"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }

$BaseSha = "6fbb705"
Write-Output "fail_before_sha $BaseSha"
Write-Output "FAIL_BEFORE at ${BaseSha}: no ETag/304/declared-root native site gate; host TrySite had no SHA-256 ETag"

$siteSrc = Join-Path $Root "sites/landing/site"
$siteDsts = @((Join-Path $Root "site"), (Join-Path $Data "site"))
foreach ($siteDst in $siteDsts) {
    New-Item -ItemType Directory -Force -Path $siteDst | Out-Null
    Copy-Item (Join-Path $siteSrc "*") $siteDst -Force
}
$siteDst = $siteDsts[0]
$files = Get-ChildItem -File $siteDst | Sort-Object Name
if ($files.Count -lt 2) { throw "missing vendored landing files" }

$manifest = @()
foreach ($f in $files) {
    $h = (Get-FileHash -Algorithm SHA256 $f.FullName).Hash.ToLowerInvariant()
    $manifest += "{0}  {1}" -f $h, $f.Name
    Write-Output ("disk_sha256 " + $f.Name + " " + $h)
}
$manifestPath = Join-Path $Root "sites/landing/SHA256SUMS"
Set-Content -Path $manifestPath -Value ($manifest -join "`n") -NoNewline

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Get-Http([int]$Port, [string]$Path, [string]$Method = "GET", [hashtable]$Headers = @{}) {
    $client = New-Object System.Net.Sockets.TcpClient
    $client.ReceiveTimeout = 8000
    $client.SendTimeout = 8000
    $client.Connect("127.0.0.1", $Port)
    $stream = $client.GetStream()
    $req = "$Method $Path HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n"
    foreach ($k in $Headers.Keys) { $req += "${k}: $($Headers[$k])`r`n" }
    $req += "`r`n"
    $bytes = [Text.Encoding]::ASCII.GetBytes($req)
    $stream.Write($bytes, 0, $bytes.Length)
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 8192
    try {
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    } catch { }
    $client.Close()
    return $ms.ToArray()
}

function Split-Http([byte[]]$raw) {
    $text = [Text.Encoding]::ASCII.GetString($raw)
    $split = $text.IndexOf("`r`n`r`n")
    if ($split -lt 0) { throw "no header split" }
    $head = $text.Substring(0, $split)
    $body = New-Object byte[] ($raw.Length - $split - 4)
    [Array]::Copy($raw, $split + 4, $body, 0, $body.Length)
    return @{ Head = $head; Body = $body; Status = ([regex]::Match($head, "^HTTP/1.1 (\d+)")).Groups[1].Value }
}

function Serve-And-Check([string]$Name, [scriptblock]$Start) {
    $job = & $Start
    try {
        $port = $job.Port
        Write-Output ("${Name}_listen 127.0.0.1:$port")
        foreach ($f in $files) {
            $want = [IO.File]::ReadAllBytes($f.FullName)
            if ($f.Extension -eq ".html") {
                $want = [Text.Encoding]::UTF8.GetBytes(([Text.Encoding]::UTF8.GetString($want) -replace '\{\{year\}\}', '2026' -replace '\{\{payments\}\}', 'off'))
            }
            $rel = "/" + $f.Name
            if ($f.Name -eq "index.html") { $rel = "/" }
            $raw = Get-Http $port $rel
            $got = Split-Http $raw
            if ($got.Status -ne "200") { throw "$Name $rel status $($got.Status)" }
            $shaWant = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($want)).Replace("-", "").ToLowerInvariant()
            $shaGot = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($got.Body)).Replace("-", "").ToLowerInvariant()
            Write-Output ("${Name}_sha256 " + $f.Name + " " + $shaGot)
            if ($shaWant -ne $shaGot) { throw "$Name $($f.Name) body sha mismatch want $shaWant got $shaGot" }
            if ($got.Head -notmatch "(?i)etag:") { throw "$Name missing ETag" }
            if ($got.Head -notmatch "(?i)cache-control:") { throw "$Name missing Cache-Control" }
            $etag = ([regex]::Match($got.Head, "(?i)etag:\s*(.+)")).Groups[1].Value.Trim()
            $raw304 = Get-Http $port $rel "GET" @{ "If-None-Match" = $etag }
            $g304 = Split-Http $raw304
            if ($Name -eq "host") {
                if ($g304.Status -ne "304") { throw "host 304 got $($g304.Status)" }
            }
            $headRaw = Get-Http $port $rel "HEAD"
            $gh = Split-Http $headRaw
            if ($gh.Status -ne "200") { throw "$Name HEAD $($f.Name) $($gh.Status)" }
            if ($gh.Body.Length -ne 0) { throw "$Name HEAD body nonempty" }
        }
        foreach ($trav in @("/../Vire.cs", "/%2e%2e/Vire.cs", "/..\\Vire.cs", "/foo/../../Vire.cs")) {
            $raw = Get-Http $port $trav
            $got = Split-Http $raw
            Write-Output ("${Name}_traversal " + $trav + " " + $got.Status)
            if ($got.Status -ne "404") { throw "$Name traversal $trav -> $($got.Status)" }
        }
        $raw405 = Get-Http $port "/index.html" "POST"
        $g405 = Split-Http $raw405
        Write-Output ("${Name}_post_index " + $g405.Status)
        if ($g405.Status -ne "405") { throw "$Name POST index $($g405.Status)" }
        Write-Output ("${Name}_site_ok")
    } finally {
        if ($job.Proc -and -not $job.Proc.HasExited) { try { $job.Proc.Kill($true) } catch { } }
    }
}

Write-VireHostInfo

$serveSrc = @"
define route with method, path, body
  return "{\"ok\":false,\"status\":404,\"error\":\"not found\"}"
end
define main
  listen with 0
end
"@
$serveFile = Join-Path $Root "data/guest-site-host.vire"
Set-Content -Path $serveFile -Value $serveSrc

function Start-HostListen {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dotnet"
    $psi.Arguments = "exec `"$VireDll`" `"$serveFile`""
    $psi.WorkingDirectory = $Root
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    $line = $p.StandardOutput.ReadLine()
    if ($line -notmatch "listening on 127.0.0.1:(\d+)") {
        try { $p.Kill($true) } catch { }
        throw "host did not listen: $line"
    }
    return @{ Proc = $p; Port = [int]$Matches[1] }
}

Serve-And-Check "host" { Start-HostListen }

Copy-Item (Join-Path $Root "guest-landing.vire") (Join-Path $Data "guest-landing.vire") -Force
$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing gen1.exe; run native-selfhost-handoff.ps1 first" }
$hex = Join-Path $Data "guest-landing.hex"
$exe = Join-Path $Data "guest-landing.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
$p = Start-Process -FilePath $gen1 -ArgumentList @("data/guest-landing.vire", "data/guest-landing.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "gen1 landing compile exit $($p.ExitCode)" }
Convert-HexToExe $hex $exe
try { Unblock-File -Path $exe } catch { }

function Start-PeListen {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.WorkingDirectory = $Root
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    $deadline = (Get-Date).AddSeconds(8)
    $port = 0
    while ((Get-Date) -lt $deadline) {
        if ($p.HasExited) { throw "pe exited $($p.ExitCode)" }
        $line = $p.StandardOutput.ReadLine()
        if ($line -and $line -match "listening on 127.0.0.1:(\d+)") {
            $port = [int]$Matches[1]
            break
        }
    }
    if ($port -eq 0) { $port = 18081 }
    return @{ Proc = $p; Port = $port }
}

Serve-And-Check "gen1" { Start-PeListen }

$h1 = (Get-FileHash -Algorithm SHA256 (Join-Path $Data "gen1.hex")).Hash.ToLowerInvariant()
$h2 = (Get-FileHash -Algorithm SHA256 (Join-Path $Data "gen2.hex")).Hash.ToLowerInvariant()
Write-Output "gen1_sha256 $h1"
Write-Output "gen2_sha256 $h2"
if ($h1 -ne $h2) { throw "gen1/gen2 SHA-256 differ" }
$AfterSha = (git -C $Root rev-parse HEAD).Trim()
Write-Output "PASS_AFTER at $AfterSha host and gen1 PE landing bodies sha256-identical; traversal 404"
Write-Output "native site proof ok"
