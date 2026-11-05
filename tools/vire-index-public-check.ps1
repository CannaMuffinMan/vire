# Public fetch policy. Private, link-local, metadata, and loopback-as-public are refused.
# A public https host must not be refused before any download. Redirects to private addresses are refused.
# No secret is printed. Does not open a public listener.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$Client = Join-Path $PSScriptRoot "vire-index.ps1"
$Pwsh = Join-Path $PSHOME "pwsh.exe"
$Dest = Join-Path $env:TEMP "vire-index-public-dest"

if (-not (Test-Path -LiteralPath $Pwsh)) { $Pwsh = "pwsh" }

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Invoke-Fetch([string]$Url) {
    $out = & $Pwsh -NoProfile -File $Client fetch $Url pinpack $Dest 2>&1
    return @{ Code = $LASTEXITCODE; Text = (($out | Out-String).Trim()) }
}

if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
New-Item -ItemType Directory -Path $Dest | Out-Null

$refused = @(
    "https://10.1.2.3/index",
    "https://192.168.1.1/index",
    "https://172.16.0.1/index",
    "https://169.254.1.1/index",
    "https://169.254.169.254/latest/meta-data",
    "https://127.0.0.1/index",
    "https://127.0.0.1:18242/index",
    "https://localhost/index",
    "https://[::1]/index",
    "https://[::ffff:127.0.0.1]/index",
    "https://0.0.0.0/index",
    "https://100.64.0.1/index",
    "https://192.88.99.1/index",
    "https://[64:ff9b:1::8.8.8.8]/index",
    "https://[64:ff9b::10.0.0.1]/index",
    "https://[2002:7f00:0001::1]/index",
    "http://8.8.8.8/index",
    "http://example.com/index",
    "https://user:pass@example.com/index"
)

foreach ($url in $refused) {
    $got = Invoke-Fetch $url
    if ($got.Code -eq 0 -or $got.Text -notmatch "refused host") {
        Fail "error: blocked url was not refused"
    }
}
Write-Output "blocked hosts refused"

$publicUrl = "https://example.com/index"
Write-Output "fetch public https host"
$pub = Invoke-Fetch $publicUrl
if ($pub.Code -eq 0) { Fail "error: unpinned public body was installed" }
if ($pub.Text -match "refused host") { Fail "error: public https host was refused" }
Write-Output "public https host allowed"
if ($pub.Text.Length -gt 0) { Write-Output $pub.Text }

$LogOut = Join-Path $env:TEMP "vire-index-public-redir.out"
$LogErr = Join-Path $env:TEMP "vire-index-public-redir.err"
$tcp = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse("127.0.0.1"), 18242)
try {
    $tcp.Start()
} catch {
    Fail "error: could not bind loopback redirect fixture"
}
try {
    $proc = Start-Process -FilePath $Pwsh -ArgumentList @("-NoProfile", "-File", $Client, "fetch", "http://127.0.0.1:18242/index", "pinpack", $Dest) -PassThru -WindowStyle Hidden -RedirectStandardOutput $LogOut -RedirectStandardError $LogErr
    $pending = $tcp.BeginAcceptTcpClient($null, $null)
    if (-not $pending.AsyncWaitHandle.WaitOne(8000)) {
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
        Fail "error: redirect fixture got no client"
    }
    $client = $tcp.EndAcceptTcpClient($pending)
    try {
        $stream = $client.GetStream()
        $stream.ReadTimeout = 8000
        $buf = New-Object byte[] 1024
        [void]$stream.Read($buf, 0, $buf.Length)
        $body = "HTTP/1.1 302 Found`r`nLocation: http://169.254.169.254/latest/meta-data`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($body)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    } finally {
        $client.Close()
    }
    if (-not $proc.WaitForExit(15000)) {
        Stop-Process -Id $proc.Id -Force
        Fail "error: redirect fetch hung"
    }
    $redirText = ""
    if (Test-Path -LiteralPath $LogErr) { $redirText = [System.IO.File]::ReadAllText($LogErr) }
    if (Test-Path -LiteralPath $LogOut) { $redirText = $redirText + [System.IO.File]::ReadAllText($LogOut) }
    $redirText = $redirText.Trim()
    if ($proc.ExitCode -eq 0 -or $redirText -notmatch "refused host") {
        Fail "error: redirect to metadata was not refused"
    }
    Write-Output "redirect to metadata refused"
} finally {
    $tcp.Stop()
}

Write-Output "vire-index-public ok"
exit 0
