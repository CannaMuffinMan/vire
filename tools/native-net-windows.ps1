# Compile a health guest with gen1, run the PE, curl GET /health, plus adversarial cases.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

Copy-Item (Join-Path $Root "guest-health.vire") (Join-Path $Data "guest-health.vire") -Force
$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing gen1.exe; run native-selfhost-handoff.ps1 first" }

$hex = Join-Path $Data "guest-health.hex"
$exe = Join-Path $Data "guest-health.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
$p = Start-Process -FilePath $gen1 -ArgumentList @("data/guest-health.vire", "data/guest-health.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "gen1 health compile exit $($p.ExitCode)" }
if (-not (Test-Path $hex)) { throw "no health hex" }
Convert-HexToExe $hex $exe
$pe = [System.IO.File]::ReadAllBytes($exe)
$ascii = [System.Text.Encoding]::ASCII.GetString($pe)
if ($ascii -notmatch "LoadLibraryA") { throw "PE missing LoadLibraryA" }
if ($ascii -notmatch "GetProcAddress") { throw "PE missing GetProcAddress" }
if ($ascii -notmatch "ws2_32.dll") { throw "PE missing ws2_32.dll" }
Write-Output "health_pe_iat LoadLibraryA GetProcAddress ws2_32.dll"

$outFile = Join-Path $Data "guest-health.out.txt"
$errFile = Join-Path $Data "guest-health.err.txt"
if (Test-Path $outFile) { Remove-Item -Force $outFile }
if (Test-Path $errFile) { Remove-Item -Force $errFile }
$server = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$deadline = (Get-Date).AddSeconds(30)
$port = $null
while ((Get-Date) -lt $deadline) {
    if (Test-Path $outFile) {
        $txt = Get-Content -Raw $outFile
        if ($txt -match "listening on 127.0.0.1:(\d+)") {
            $port = [int]$Matches[1]
            break
        }
    }
    if ($server.HasExited) { throw "health server exited $($server.ExitCode) early" }
    Start-Sleep -Milliseconds 100
}
if (-not $port) { throw "did not print listening port" }
if ($port -lt 1024) { throw "bound port $port" }
Write-Output "health_listen 127.0.0.1:$port"

function Send-Raw([int]$Port, [string]$Payload, [int]$WaitMs = 3000) {
    $client = New-Object System.Net.Sockets.TcpClient
    $client.ReceiveTimeout = $WaitMs
    $client.SendTimeout = $WaitMs
    $client.Connect("127.0.0.1", $Port)
    $stream = $client.GetStream()
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Payload)
    $stream.Write($bytes, 0, $bytes.Length)
    $buf = New-Object byte[] 8192
    $n = 0
    try { $n = $stream.Read($buf, 0, $buf.Length) } catch { $n = 0 }
    $client.Close()
    return [System.Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Max(0, $n))
}

$health = Send-Raw $port "GET /health HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n"
Write-Output "health_curl_result $health"
if ($health -notmatch "^HTTP/1.1 200 ") { throw "health status not 200" }
if ($health -notmatch '"ok":true') { throw "health body missing ok true" }
if ($health -match "(?i)set-cookie") { throw "unexpected set-cookie" }

$mal = Send-Raw $port "GET /health`r`n`r`n"
Write-Output "adversary_malformed_line $mal"
if ($mal -notmatch "^HTTP/1.1 400 ") { throw "malformed line expected 400" }

$huge = "GET / HTTP/1.1`r`nHost: x`r`n" + ("X: " + ("y" * 200) + "`r`n") * 80 + "`r`n"
$big = Send-Raw $port $huge
Write-Output "adversary_oversize_headers $($big.Substring(0, [Math]::Min(80, $big.Length)))"
if ($big -notmatch "^HTTP/1.1 431 ") { throw "oversize headers expected 431" }

$inject = Send-Raw $port "GET /health HTTP/1.1`r`nHost: x`r`nX-Foo: bar`r`nSet-Cookie: stolen`r`n`r`n"
Write-Output "adversary_crlf_request_header $($inject.Substring(0, [Math]::Min(120, $inject.Length)))"
if ($inject -match "(?i)set-cookie: stolen") { throw "request header leaked into response" }

$partial = $null
$c = New-Object System.Net.Sockets.TcpClient
$c.ReceiveTimeout = 8000
$c.Connect("127.0.0.1", $port)
$s = $c.GetStream()
$pbytes = [System.Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`n")
$s.Write($pbytes, 0, $pbytes.Length)
$buf = New-Object byte[] 1024
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$n = 0
try { $n = $s.Read($buf, 0, $buf.Length) } catch { $n = 0 }
$sw.Stop()
$c.Close()
$partial = [System.Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Max(0, $n))
Write-Output "adversary_slowloris_ms $($sw.ElapsedMilliseconds) $partial"
if ($sw.ElapsedMilliseconds -lt 1000) { throw "slowloris returned too fast" }
if ($n -gt 0 -and $partial -notmatch "408") { throw "slowloris expected timeout 408" }

try { $server.Kill() } catch { }
Write-Output "native net windows ok"
