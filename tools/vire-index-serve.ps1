# Serve tests/index-fixture on 127.0.0.1:18242 only. No other address or port.
# GET /index -> index file. GET /pkg/<name>/<version>/lib.vire -> that file.
# Any other path is 404. No directory listing.
param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 18242
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

if ($Port -ne 18242) { Fail "error: refused port" }

$Repo = Split-Path -Parent $PSScriptRoot
$Fixture = [System.IO.Path]::GetFullPath((Join-Path $Repo "tests/index-fixture"))
$IndexFile = [System.IO.Path]::GetFullPath((Join-Path $Fixture "index"))
if (-not (Test-Path -LiteralPath $IndexFile -PathType Leaf)) { Fail "error: missing index" }

function Is-Reparse([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Inside-Fixture([string]$Full) {
    $root = $Fixture
    if (-not $root.EndsWith("\") -and -not $root.EndsWith("/")) {
        $root = $root + [System.IO.Path]::DirectorySeparatorChar
    }
    return $Full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-Package([string]$Name, [string]$Version) {
    if ($Name -notmatch '^[A-Za-z0-9_]+$') { return $null }
    if ($Version -notmatch '^[A-Za-z0-9._-]+$' -or $Version -eq "." -or $Version -eq ".." -or $Version.Contains("..")) {
        return $null
    }
    $rel = "pkgs/" + $Name + "/" + $Version + "/lib.vire"
    $full = [System.IO.Path]::GetFullPath((Join-Path $Fixture $rel))
    if (-not (Inside-Fixture $full)) { return $null }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    if (Is-Reparse $full) { return $null }
    $parent = Split-Path -Parent $full
    while ($parent.Length -ge $Fixture.Length) {
        if (Is-Reparse $parent) { return $null }
        if ($parent -eq $Fixture) { break }
        $next = Split-Path -Parent $parent
        if ($next -eq $parent) { break }
        $parent = $next
    }
    return $full
}

function Send-Bytes([System.Net.Sockets.NetworkStream]$Stream, [int]$Status, [string]$Reason, [byte[]]$Body) {
    $head = "HTTP/1.1 $Status $Reason`r`nContent-Length: $($Body.Length)`r`nContent-Type: application/octet-stream`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $Stream.Write($hb, 0, $hb.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}

function Read-Request([System.Net.Sockets.NetworkStream]$Stream) {
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 1024
    $Stream.ReadTimeout = 5000
    while ($ms.Length -lt 8192) {
        $n = 0
        try { $n = $Stream.Read($buf, 0, $buf.Length) } catch { return $null }
        if ($n -le 0) { break }
        $ms.Write($buf, 0, $n)
        $text = [System.Text.Encoding]::ASCII.GetString($ms.ToArray())
        $cut = $text.IndexOf("`r`n`r`n")
        if ($cut -ge 0) { return $text.Substring(0, $cut) }
    }
    return $null
}

$bind = [System.Net.IPAddress]::Parse("127.0.0.1")
$listener = New-Object System.Net.Sockets.TcpListener($bind, 18242)
try {
    $listener.Start()
} catch {
    Fail ("error: could not listen on 127.0.0.1:18242: " + $_.Exception.Message)
}

Write-Output "listening 127.0.0.1:18242"
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.NoDelay = $true
            $stream = $client.GetStream()
            $req = Read-Request $stream
            if ($null -eq $req) { continue }
            $line = $req.Split("`n")[0].TrimEnd("`r")
            $parts = $line.Split(" ")
            $path = $null
            $body = $null
            $status = 404
            $reason = "Not Found"
            if ($parts.Length -ge 2 -and $parts[0] -eq "GET") {
                $path = $parts[1]
                if ($path.IndexOf("?") -ge 0) { $path = $null }
                elseif ($path.IndexOf("#") -ge 0) { $path = $null }
                elseif ($path.Contains("%") -or $path.Contains("\") -or $path.Contains("..")) { $path = $null }
            }
            if ($path -eq "/index") {
                if (Is-Reparse $IndexFile) { $path = $null }
                else {
                    $body = [System.IO.File]::ReadAllBytes($IndexFile)
                    $status = 200
                    $reason = "OK"
                }
            } elseif ($null -ne $path -and $path.StartsWith("/pkg/")) {
                $segs = $path.Substring(5).Split("/")
                if ($segs.Length -eq 3 -and $segs[2] -eq "lib.vire" -and $segs[0].Length -gt 0 -and $segs[1].Length -gt 0) {
                    $file = Resolve-Package $segs[0] $segs[1]
                    if ($null -ne $file) {
                        $body = [System.IO.File]::ReadAllBytes($file)
                        $status = 200
                        $reason = "OK"
                    }
                }
            }
            if ($null -eq $body) { $body = New-Object byte[] 0 }
            Send-Bytes $stream $status $reason $body
        } catch {
            # Client gone or a bad request. Keep serving the next connection.
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
