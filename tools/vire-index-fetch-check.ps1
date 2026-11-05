# Start the loopback index server, fetch pinpack, check the file hash, show a bad-host refusal, stop.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$Root = Split-Path -Parent $PSScriptRoot
$Serve = Join-Path $PSScriptRoot "vire-index-serve.ps1"
$Client = Join-Path $PSScriptRoot "vire-index.ps1"
$Fixture = Join-Path $Root "tests/index-fixture"
$IndexFile = Join-Path $Fixture "index"
$LibFile = Join-Path $Fixture "pkgs/pinpack/1.0.0/lib.vire"
$Pwsh = Join-Path $PSHOME "pwsh.exe"
$LogOut = Join-Path $env:TEMP "vire-index-fetch-check.out"
$LogErr = Join-Path $env:TEMP "vire-index-fetch-check.err"
$Dest = Join-Path $env:TEMP "vire-index-fetch-dest"

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

if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
New-Item -ItemType Directory -Path $Dest | Out-Null

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

    $fetchUrl = "http://127.0.0.1:18242/"
    Write-Output ("fetch " + $fetchUrl + " pinpack " + $Dest)
    & $Pwsh -NoProfile -File $Client fetch $fetchUrl pinpack $Dest
    if ($LASTEXITCODE -ne 0) { Fail "error: fetch failed" }

    $gotLib = Join-Path $Dest "deps/pinpack/lib.vire"
    if (-not (Test-Path -LiteralPath $gotLib -PathType Leaf)) { Fail "error: missing fetched lib" }
    $gotHash = Sha256-File $gotLib
    $diskHash = Sha256-File $LibFile
    $line = ([System.IO.File]::ReadAllText($IndexFile)).Trim()
    $pinned = $line.Split(" ")[2]
    if ($gotHash -ne $diskHash -or $gotHash -ne $pinned) {
        Fail ("error: hash mismatch got " + $gotHash + " disk " + $diskHash + " index " + $pinned)
    }
    $lockText = [System.IO.File]::ReadAllText((Join-Path $Dest "deps.lock"))
    if ($lockText.Trim() -ne ("pinpack " + $gotHash)) { Fail "error: deps.lock mismatch" }
    Write-Output ("hash " + $gotHash)

    $badUrl = "http://example.com/pkg/pinpack/1.0.0/lib.vire"
    Write-Output ("fetch " + $badUrl + " pinpack " + $Dest)
    $bad = & $Pwsh -NoProfile -File $Client fetch $badUrl pinpack $Dest 2>&1
    $badCode = $LASTEXITCODE
    $badText = ($bad | Out-String).Trim()
    Write-Output $badText
    if ($badCode -eq 0 -or $badText -notmatch "refused host") { Fail "error: bad host was not refused" }
    Write-Output "bad host refused"
    Write-Output "vire-index-fetch ok"
} finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
        $proc.WaitForExit()
    }
}
exit 0
