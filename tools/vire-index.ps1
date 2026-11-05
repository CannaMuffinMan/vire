# Local package index.
# Index lines: name version sha256
# sha256 is 64 lowercase hex of the raw lib.vire bytes.
# Packages sit beside the index: pkgs/<name>/<version>/lib.vire
# install <index> <name> <destfolder>
# Copies to destfolder/deps/<name>/lib.vire only when the hash matches.
# fetch <url> <name> <destfolder> [sha256]
# Loopback url must be http://127.0.0.1:18242/... .
# Any other url must be https on a public address. Private, link-local,
# loopback, metadata, NAT64 local-use, and 6to4 anycast are refused.
# Downloads /index and /pkg/<name>/<version>/lib.vire from that origin.
# A public fetch must pass the expected 64-hex SHA-256. The index line and
# the body must both match it. Redirects are checked again and never followed
# to a private or loopback address. Body cap is 1 MB.
# A mismatch exits 1 and writes nothing. A damaged deps.lock is refused.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Command,
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Index,
    [Parameter(Mandatory = $true, Position = 2)]
    [string]$Name,
    [Parameter(Mandatory = $true, Position = 3)]
    [string]$DestFolder,
    [Parameter(Mandatory = $false, Position = 4)]
    [string]$ExpectedHash = ""
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Is-Reparse([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Sha256-Bytes([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Parse-Index([string]$IndexText, [string]$Want) {
    $pinned = $null
    $seen = @{}
    foreach ($rawLine in $IndexText.Split("`n")) {
        if ($rawLine.Length -eq 0) { continue }
        $parts = $rawLine.Split(" ")
        if ($parts.Length -ne 3) { Fail "error: index is damaged" }
        $pkg = $parts[0]
        $ver = $parts[1]
        $hex = $parts[2]
        if ($pkg -notmatch '^[A-Za-z0-9_]+$') { Fail "error: index is damaged" }
        if ($ver -notmatch '^[A-Za-z0-9._-]+$' -or $ver -eq "." -or $ver -eq ".." -or $ver.Contains("..")) {
            Fail "error: index is damaged"
        }
        if ($hex -notmatch '^[0-9a-f]{64}$') { Fail "error: index is damaged" }
        if ($seen.ContainsKey($pkg)) { Fail "error: index is damaged" }
        $seen[$pkg] = $true
        if ($pkg -eq $Want) { $pinned = @{ Version = $ver; Hex = $hex } }
    }
    if ($null -eq $pinned) { Fail "error: missing package" }
    return $pinned
}

function Resolve-Inside([string]$Relative) {
    if ($Relative.IndexOf(":") -ge 0) { Fail "error: path leaves the destfolder" }
    $rootFull = $DestFolder
    if (-not $rootFull.EndsWith("\") -and -not $rootFull.EndsWith("/")) {
        $rootFull = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    }
    $full = [System.IO.Path]::GetFullPath((Join-Path $DestFolder $Relative))
    if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "error: path leaves the destfolder"
    }
    return $full
}

function Write-Pinned([byte[]]$Bytes, [string]$Hash, [string]$Version) {
    $lockPath = Resolve-Inside "deps.lock"
    $utf8 = New-Object System.Text.UTF8Encoding $false
    if (Test-Path -LiteralPath $lockPath) {
        if (Is-Reparse $lockPath) { Fail "error: path leaves the destfolder" }
        $lockText = [System.IO.File]::ReadAllText($lockPath, $utf8).Replace("`r`n", "`n").Replace("`r", "`n")
        $lockNames = New-Object System.Collections.Generic.List[string]
        $lockHex = @{}
        foreach ($rawLine in $lockText.Split("`n")) {
            if ($rawLine.Length -eq 0) { continue }
            $space = $rawLine.IndexOf(" ")
            if ($space -le 0 -or $rawLine.IndexOf(" ", $space + 1) -ge 0) { Fail "error: deps.lock is damaged" }
            $lockName = $rawLine.Substring(0, $space)
            $lockHash = $rawLine.Substring($space + 1)
            if ($lockName -notmatch '^[A-Za-z0-9_]+$' -or $lockHash -notmatch '^[0-9a-f]{64}$' -or $lockHex.ContainsKey($lockName)) {
                Fail "error: deps.lock is damaged"
            }
            $lockNames.Add($lockName)
            $lockHex[$lockName] = $lockHash
        }
    } else {
        $lockNames = New-Object System.Collections.Generic.List[string]
        $lockHex = @{}
    }

    $destLib = Resolve-Inside ("deps/" + $Name + "/lib.vire")
    $destDir = Split-Path -Parent $destLib
    if (Test-Path -LiteralPath $destDir) {
        if (Is-Reparse $destDir) { Fail "error: path leaves the destfolder" }
    }
    if (Test-Path -LiteralPath $destLib) {
        if (Is-Reparse $destLib) { Fail "error: path leaves the destfolder" }
    }
    $depsRoot = Resolve-Inside "deps"
    if (Test-Path -LiteralPath $depsRoot) {
        if (Is-Reparse $depsRoot) { Fail "error: path leaves the destfolder" }
    }

    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $tmpLib = $destLib + ".tmp"
    [System.IO.File]::WriteAllBytes($tmpLib, $Bytes)
    [System.IO.File]::Move($tmpLib, $destLib, $true)

    if ($lockHex.ContainsKey($Name)) {
        $lockHex[$Name] = $Hash
    } else {
        $lockNames.Add($Name)
        $lockHex[$Name] = $Hash
    }
    $sb = New-Object System.Text.StringBuilder
    foreach ($lockName in $lockNames) {
        [void]$sb.Append($lockName)
        [void]$sb.Append(" ")
        [void]$sb.Append($lockHex[$lockName])
        [void]$sb.Append("`n")
    }
    $tmpLock = $lockPath + ".tmp"
    [System.IO.File]::WriteAllText($tmpLock, $sb.ToString(), $utf8)
    [System.IO.File]::Move($tmpLock, $lockPath, $true)
    Write-Output ("installed " + $Name + " " + $Version + " " + $Hash)
}

$script:FetchTypeReady = $false

function Ensure-FetchType {
    if ($script:FetchTypeReady) { return }
    $code = @"
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;

public sealed class VireIndexFetch {
    public int Code;
    public string Location;
    public byte[] Body;
    public string Error;

    public static VireIndexFetch Get(string url, IPAddress pin) {
        VireIndexFetch result = new VireIndexFetch();
        result.Location = "";
        result.Body = new byte[0];
        SocketsHttpHandler handler = new SocketsHttpHandler();
        handler.AllowAutoRedirect = false;
        handler.UseProxy = false;
        handler.ConnectCallback = (context, token) => ConnectPinned(pin, context.DnsEndPoint.Port, token);
        using (HttpClient client = new HttpClient(handler))
        using (CancellationTokenSource cancel = new CancellationTokenSource(TimeSpan.FromSeconds(8))) {
            client.Timeout = Timeout.InfiniteTimeSpan;
            try {
                HttpResponseMessage resp = client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancel.Token).GetAwaiter().GetResult();
                using (resp) {
                    result.Code = (int)resp.StatusCode;
                    result.Location = resp.Headers.Location == null ? "" : resp.Headers.Location.ToString();
                    if (result.Code < 200 || result.Code >= 300) return result;
                    using (Stream stream = resp.Content.ReadAsStream()) {
                        MemoryStream ms = new MemoryStream();
                        byte[] buf = new byte[8192];
                        int total = 0;
                        while (true) {
                            int n = stream.ReadAsync(buf, 0, buf.Length, cancel.Token).GetAwaiter().GetResult();
                            if (n <= 0) break;
                            total += n;
                            if (total > 1000000) {
                                result.Error = "large";
                                return result;
                            }
                            ms.Write(buf, 0, n);
                        }
                        result.Body = ms.ToArray();
                    }
                }
            } catch (Exception) {
                result.Error = "network";
            }
        }
        return result;
    }

    static async ValueTask<Stream> ConnectPinned(IPAddress pin, int port, CancellationToken token) {
        Socket socket = new Socket(pin.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
        try {
            await socket.ConnectAsync(pin, port, token).ConfigureAwait(false);
            return new NetworkStream(socket, true);
        } catch (Exception) {
            socket.Dispose();
            throw;
        }
    }
}
"@
    Add-Type -TypeDefinition $code -Language CSharp
    $script:FetchTypeReady = $true
}

function Test-Zeros([byte[]]$Bits, [int]$At, [int]$Count) {
    for ($n = 0; $n -lt $Count; $n++) {
        if ($Bits[$At + $n] -ne 0) { return $false }
    }
    return $true
}

function Test-PublicV4([byte[]]$Part) {
    if ($null -eq $Part -or $Part.Length -ne 4) { return $false }
    if ($Part[0] -eq 0 -or $Part[0] -eq 10 -or $Part[0] -eq 127) { return $false }
    if ($Part[0] -eq 169 -and $Part[1] -eq 254) { return $false }
    if ($Part[0] -eq 172 -and $Part[1] -ge 16 -and $Part[1] -le 31) { return $false }
    if ($Part[0] -eq 192 -and $Part[1] -eq 168) { return $false }
    if ($Part[0] -eq 100 -and $Part[1] -ge 64 -and $Part[1] -le 127) { return $false }
    if ($Part[0] -eq 198 -and ($Part[1] -eq 18 -or $Part[1] -eq 19)) { return $false }
    if ($Part[0] -eq 192 -and $Part[1] -eq 88 -and $Part[2] -eq 99) { return $false }
    if ($Part[0] -eq 192 -and $Part[1] -eq 0 -and $Part[2] -eq 0) { return $false }
    if ($Part[0] -eq 192 -and $Part[1] -eq 0 -and $Part[2] -eq 2) { return $false }
    if ($Part[0] -eq 198 -and $Part[1] -eq 51 -and $Part[2] -eq 100) { return $false }
    if ($Part[0] -eq 203 -and $Part[1] -eq 0 -and $Part[2] -eq 113) { return $false }
    if ($Part[0] -ge 224) { return $false }
    return $true
}

function Test-PublicAddress([System.Net.IPAddress]$Address) {
    if ($null -eq $Address) { return $false }
    if ([System.Net.IPAddress]::IsLoopback($Address)) { return $false }
    if ($Address.IsIPv4MappedToIPv6) { return Test-PublicAddress $Address.MapToIPv4() }
    if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return Test-PublicV4 $Address.GetAddressBytes()
    }
    if ($Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) { return $false }
    $bits = $Address.GetAddressBytes()
    if ($bits.Length -ne 16) { return $false }
    if (Test-Zeros $bits 0 16) { return $false }
    if ((Test-Zeros $bits 0 15) -and $bits[15] -eq 1) { return $false }
    if (Test-Zeros $bits 0 12) {
        return Test-PublicAddress ([System.Net.IPAddress]::new([byte[]]@($bits[12], $bits[13], $bits[14], $bits[15])))
    }
    if ((Test-Zeros $bits 0 10) -and $bits[10] -eq 0xff -and $bits[11] -eq 0xff) {
        return Test-PublicAddress ([System.Net.IPAddress]::new([byte[]]@($bits[12], $bits[13], $bits[14], $bits[15])))
    }
    if ((Test-Zeros $bits 0 8) -and $bits[8] -eq 0xff -and $bits[9] -eq 0xff -and $bits[10] -eq 0 -and $bits[11] -eq 0) {
        return Test-PublicAddress ([System.Net.IPAddress]::new([byte[]]@($bits[12], $bits[13], $bits[14], $bits[15])))
    }
    if ($bits[0] -eq 0x20 -and $bits[1] -eq 0x02) {
        return Test-PublicAddress ([System.Net.IPAddress]::new([byte[]]@($bits[2], $bits[3], $bits[4], $bits[5])))
    }
    if ($bits[0] -eq 0x00 -and $bits[1] -eq 0x64 -and $bits[2] -eq 0xff -and $bits[3] -eq 0x9b -and (Test-Zeros $bits 4 8)) {
        return Test-PublicAddress ([System.Net.IPAddress]::new([byte[]]@($bits[12], $bits[13], $bits[14], $bits[15])))
    }
    if ($bits[0] -eq 0x00 -and $bits[1] -eq 0x64 -and $bits[2] -eq 0xff -and $bits[3] -eq 0x9b -and $bits[4] -eq 0x00 -and $bits[5] -eq 0x01) {
        return $false
    }
    if ($bits[0] -eq 0x20 -and $bits[1] -eq 0x01 -and $bits[2] -eq 0x00 -and $bits[3] -eq 0x00) { return $false }
    if ($bits[0] -eq 0x20 -and $bits[1] -eq 0x01 -and $bits[2] -eq 0x0d -and $bits[3] -eq 0xb8) { return $false }
    if ($bits[0] -eq 0xff) { return $false }
    if ($bits[0] -eq 0xfe -and ($bits[1] -band 0xc0) -eq 0x80) { return $false }
    if ($bits[0] -eq 0xfe -and ($bits[1] -band 0xc0) -eq 0xc0) { return $false }
    if (($bits[0] -band 0xfe) -eq 0xfc) { return $false }
    return $true
}

function Test-ObfuscatedHost([string]$HostName) {
    if ($HostName -match '^\d+$') { return $true }
    if ($HostName -match '(?i)^0x') { return $true }
    if ($HostName -match '^\d+(\.\d+){1,2}$') { return $true }
    if ($HostName -match '^\d{1,3}(\.\d{1,3}){3}$') {
        foreach ($part in $HostName.Split(".")) {
            if ($part.Length -gt 1 -and $part.StartsWith("0")) { return $true }
        }
    }
    return $false
}

function Get-UrlHost([System.Uri]$Uri) {
    $hostName = $Uri.IdnHost
    if ([string]::IsNullOrEmpty($hostName)) { $hostName = $Uri.Host }
    return $hostName.Trim().TrimEnd(".").ToLowerInvariant()
}

function Test-LoopbackFixture([System.Uri]$Uri, [string]$Raw) {
    if ($Uri.Scheme -ne "http") { return $false }
    if ($Uri.Port -ne 18242) { return $false }
    if ((Get-UrlHost $Uri) -ne "127.0.0.1") { return $false }
    if (-not [string]::IsNullOrEmpty($Uri.UserInfo)) { return $false }
    if (-not $Raw.StartsWith("http://127.0.0.1:18242/")) { return $false }
    return $true
}

function Resolve-PublicPin([string]$HostName) {
    if ($HostName -eq "localhost" -or $HostName.EndsWith(".localhost")) { Fail "error: refused host" }
    if ($HostName -eq "metadata.google.internal" -or $HostName -eq "metadata.google.internal.") { Fail "error: refused host" }
    if (Test-ObfuscatedHost $HostName) { Fail "error: refused host" }
    $literal = $null
    if ([System.Net.IPAddress]::TryParse($HostName, [ref]$literal)) {
        if (-not (Test-PublicAddress $literal)) { Fail "error: refused host" }
        return $literal
    }
    $addresses = $null
    try { $addresses = [System.Net.Dns]::GetHostAddresses($HostName) } catch { Fail "error: could not check that address" }
    if ($null -eq $addresses -or $addresses.Length -eq 0) { Fail "error: could not check that address" }
    foreach ($address in $addresses) {
        if (-not (Test-PublicAddress $address)) { Fail "error: refused host" }
    }
    return $addresses[0]
}

function Get-Origin([System.Uri]$Uri) {
    return $Uri.GetLeftPart([System.UriPartial]::Authority)
}

function Resolve-Redirect([string]$Current, [string]$Location) {
    if ([string]::IsNullOrEmpty($Location)) { Fail "error: refused host" }
    $next = $null
    $absolute = $false
    try { $absolute = [System.Uri]::TryCreate($Location, [System.UriKind]::Absolute, [ref]$next) } catch { Fail "error: refused host" }
    if (-not $absolute) {
        $base = $null
        if (-not [System.Uri]::TryCreate($Current, [System.UriKind]::Absolute, [ref]$base)) { Fail "error: refused host" }
        try { $next = New-Object System.Uri($base, $Location) } catch { Fail "error: refused host" }
    }
    return $next.AbsoluteUri
}

function Download-Checked([string]$Url, [bool]$AllowLoopback) {
    Ensure-FetchType
    $current = $Url
    for ($hop = 0; $hop -le 3; $hop++) {
        $uri = $null
        if (-not [System.Uri]::TryCreate($current, [System.UriKind]::Absolute, [ref]$uri)) { Fail "error: refused host" }
        if (-not [string]::IsNullOrEmpty($uri.UserInfo)) { Fail "error: refused host" }
        $pin = $null
        if (Test-LoopbackFixture $uri $current) {
            if (-not $AllowLoopback) { Fail "error: refused host" }
            $pin = [System.Net.IPAddress]::Parse("127.0.0.1")
        } else {
            if ($uri.Scheme -ne "https") { Fail "error: refused host" }
            $pin = Resolve-PublicPin (Get-UrlHost $uri)
        }
        $got = [VireIndexFetch]::Get($current, $pin)
        if ($got.Error -eq "large") { Fail "error: response is too large" }
        if ($got.Error -eq "network") { Fail "error: download failed" }
        if ($got.Code -ge 300 -and $got.Code -le 399) {
            if ($hop -eq 3) { Fail "error: too many redirects" }
            $current = Resolve-Redirect $current $got.Location
            $AllowLoopback = $false
            continue
        }
        if ($got.Code -ne 200) { Fail "error: download failed" }
        return $got.Body
    }
    Fail "error: too many redirects"
}

if ($Command -ne "install" -and $Command -ne "fetch") { Fail "error: unknown command" }
if ($Name -notmatch '^[A-Za-z0-9_]+$') { Fail "error: bad package name" }

$Repo = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($DestFolder)) { $DestFolder = Join-Path $Repo $DestFolder }
$DestFolder = [System.IO.Path]::GetFullPath($DestFolder)
if (-not (Test-Path -LiteralPath $DestFolder -PathType Container)) { Fail "error: missing destfolder" }
if (Is-Reparse $DestFolder) { Fail "error: path leaves the destfolder" }

$utf8 = New-Object System.Text.UTF8Encoding $false

if ($Command -eq "fetch") {
    $rootUri = $null
    if (-not [System.Uri]::TryCreate($Index, [System.UriKind]::Absolute, [ref]$rootUri)) { Fail "error: refused host" }
    $loopback = Test-LoopbackFixture $rootUri $Index
    if (-not $loopback) {
        if (-not [string]::IsNullOrEmpty($rootUri.UserInfo)) { Fail "error: refused host" }
        if ($rootUri.Scheme -ne "https") { Fail "error: refused host" }
        [void](Resolve-PublicPin (Get-UrlHost $rootUri))
        if ($ExpectedHash -notmatch '^[0-9a-f]{64}$') { Fail "error: missing pin" }
    } elseif ($ExpectedHash.Length -gt 0 -and $ExpectedHash -notmatch '^[0-9a-f]{64}$') {
        Fail "error: missing pin"
    }
    $origin = Get-Origin $rootUri
    $indexBytes = Download-Checked ($origin + "/index") $true
    $indexText = $utf8.GetString($indexBytes).Replace("`r`n", "`n").Replace("`r", "`n")
    $pinned = Parse-Index $indexText $Name
    if ($ExpectedHash.Length -gt 0 -and $pinned.Hex -ne $ExpectedHash) { Fail "error: hash mismatch" }
    if (-not $loopback -and $pinned.Hex -ne $ExpectedHash) { Fail "error: hash mismatch" }
    $pkgUrl = $origin + "/pkg/" + $Name + "/" + $pinned.Version + "/lib.vire"
    $bytes = Download-Checked $pkgUrl $true
    $hash = Sha256-Bytes $bytes
    if ($hash -ne $pinned.Hex) { Fail "error: hash mismatch" }
    if ($ExpectedHash.Length -gt 0 -and $hash -ne $ExpectedHash) { Fail "error: hash mismatch" }
    Write-Pinned $bytes $hash $pinned.Version
    exit 0
}

if (-not [System.IO.Path]::IsPathRooted($Index)) { $Index = Join-Path $Repo $Index }
$Index = [System.IO.Path]::GetFullPath($Index)

if (-not (Test-Path -LiteralPath $Index -PathType Leaf)) { Fail "error: missing index" }
if (Is-Reparse $Index) { Fail "error: path leaves the index" }

$indexText = [System.IO.File]::ReadAllText($Index, $utf8).Replace("`r`n", "`n").Replace("`r", "`n")
$pinned = Parse-Index $indexText $Name

$indexDir = Split-Path -Parent $Index
$libSrc = Join-Path $indexDir ("pkgs/" + $Name + "/" + $pinned.Version + "/lib.vire")
$libSrc = [System.IO.Path]::GetFullPath($libSrc)
$indexRoot = $indexDir
if (-not $indexRoot.EndsWith("\") -and -not $indexRoot.EndsWith("/")) {
    $indexRoot = $indexRoot + [System.IO.Path]::DirectorySeparatorChar
}
if (-not $libSrc.StartsWith($indexRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Fail "error: path leaves the index"
}
if (-not (Test-Path -LiteralPath $libSrc -PathType Leaf)) { Fail "error: missing package" }
if (Is-Reparse $libSrc) { Fail "error: path leaves the index" }
$parent = Split-Path -Parent $libSrc
while ($parent.Length -ge $indexDir.Length) {
    if (Is-Reparse $parent) { Fail "error: path leaves the index" }
    if ($parent -eq $indexDir) { break }
    $next = Split-Path -Parent $parent
    if ($next -eq $parent) { break }
    $parent = $next
}

$bytes = [System.IO.File]::ReadAllBytes($libSrc)
$hash = Sha256-Bytes $bytes
if ($hash -ne $pinned.Hex) { Fail "error: hash mismatch" }

Write-Pinned $bytes $hash $pinned.Version
exit 0
