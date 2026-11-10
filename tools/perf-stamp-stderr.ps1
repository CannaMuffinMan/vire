param(
    [Parameter(Mandatory = $true)][string]$ErrPath,
    [Parameter(Mandatory = $true)][string]$StampPath,
    [Parameter(Mandatory = $true)][int]$WatchPid
)
$ErrorActionPreference = "Stop"
$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-Path -LiteralPath $ErrPath)) {
    if ((Get-Date) -gt $deadline) { throw "missing $ErrPath" }
    Start-Sleep -Milliseconds 20
}
$fs = [System.IO.File]::Open($ErrPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = New-Object System.IO.StreamReader($fs)
try {
    Set-Content -LiteralPath $StampPath -Value "" -NoNewline
    while ($true) {
        $line = $sr.ReadLine()
        if ($null -ne $line) {
            $t = [DateTime]::UtcNow.ToString("o")
            Add-Content -LiteralPath $StampPath -Value ($t + " " + $line)
            continue
        }
        $alive = $false
        try { $alive = (Get-Process -Id $WatchPid -ErrorAction Stop) -ne $null } catch { $alive = $false }
        if (-not $alive) { break }
        Start-Sleep -Milliseconds 20
    }
    while ($null -ne ($line = $sr.ReadLine())) {
        $t = [DateTime]::UtcNow.ToString("o")
        Add-Content -LiteralPath $StampPath -Value ($t + " " + $line)
    }
}
finally {
    $sr.Dispose()
    $fs.Dispose()
}
