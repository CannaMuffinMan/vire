# Start the loopback index server, fetch /index and one package, check the hash, require 404, stop.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$Root = Split-Path -Parent $PSScriptRoot
$Serve = Join-Path $PSScriptRoot "vire-index-serve.ps1"
$Fixture = Join-Path $Root "tests/index-fixture"
$IndexFile = Join-Path $Fixture "index"
$LibFile = Join-Path $Fixture "pkgs/pinpack/1.0.0/lib.vire"
$Pwsh = Join-Path $PSHOME "pwsh.exe"
$LogOut = Join-Path $env:TEMP "vire-index-serve-check.out"
$LogErr = Join-Path $env:TEMP "vire-index-serve-check.err"
$OutIndex = Join-Path $env:TEMP "vire-index-serve-index.bin"
$OutLib = Join-Path $env:TEMP "vire-index-serve-lib.vire"

if (-not (Test-Path -LiteralPath $Pwsh)) { $Pwsh = "pwsh" }

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Sha256-File([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace("-", "").ToLowerInvariant()
        } finally {
            $fs.Dispose()
        }
    } finally {
        $sha.Dispose()
    }
}

$proc = Start-Process -FilePath $Pwsh -ArgumentList @("-NoProfile", "-File", $Serve) -PassThru -WindowStyle Hidden -RedirectStandardOutput $LogOut -RedirectStandardError $LogErr
try {
    $up = $false
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if ($proc.HasExited) { break }
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect("127.0.0.1", 18242)
            $up = $true
            break
        } catch {
            Start-Sleep -Milliseconds 100
        } finally {
            $tcp.Dispose()
        }
    }
    if (-not $up) {
        $detail = ""
        if (Test-Path -LiteralPath $LogErr) { $detail = [System.IO.File]::ReadAllText($LogErr) }
        if (Test-Path -LiteralPath $LogOut) { $detail = $detail + [System.IO.File]::ReadAllText($LogOut) }
        Fail ("error: server did not listen on 127.0.0.1:18242 " + $detail)
    }

    Write-Output "GET http://127.0.0.1:18242/index"
    Invoke-WebRequest -Uri "http://127.0.0.1:18242/index" -UseBasicParsing -OutFile $OutIndex | Out-Null
    $wantIndex = [System.IO.File]::ReadAllBytes($IndexFile)
    $gotIndex = [System.IO.File]::ReadAllBytes($OutIndex)
    if (-not [System.Linq.Enumerable]::SequenceEqual($wantIndex, $gotIndex)) { Fail "error: index bytes differ" }
    Write-Output "index bytes match"

    Write-Output "GET http://127.0.0.1:18242/pkg/pinpack/1.0.0/lib.vire"
    Invoke-WebRequest -Uri "http://127.0.0.1:18242/pkg/pinpack/1.0.0/lib.vire" -UseBasicParsing -OutFile $OutLib | Out-Null
    $gotHash = Sha256-File $OutLib
    $diskHash = Sha256-File $LibFile
    $line = ([System.IO.File]::ReadAllText($IndexFile)).Trim()
    $pinned = $line.Split(" ")[2]
    if ($gotHash -ne $diskHash -or $gotHash -ne $pinned) {
        Fail ("error: hash mismatch got " + $gotHash + " disk " + $diskHash + " index " + $pinned)
    }
    Write-Output ("hash " + $gotHash)

    Write-Output "GET http://127.0.0.1:18242/pkgs"
    $status = 0
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:18242/pkgs" -UseBasicParsing -OutFile (Join-Path $env:TEMP "vire-index-serve-404.bin") | Out-Null
        Fail "error: other path was not 404"
    } catch {
        $resp = $_.Exception.Response
        if ($null -ne $resp) { $status = [int]$resp.StatusCode }
    }
    if ($status -ne 404) { Fail ("error: expected 404 got " + $status) }
    Write-Output "other path 404"
    Write-Output "vire-index-serve ok"
} finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
        $proc.WaitForExit()
    }
}
exit 0
