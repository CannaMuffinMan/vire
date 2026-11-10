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

function Get-PeImportNames([byte[]]$pe) {
    $names = New-Object System.Collections.Generic.List[string]
    $peOff = [BitConverter]::ToInt32($pe, 60)
    $magic = [BitConverter]::ToUInt16($pe, $peOff + 24)
    $dirOff = if ($magic -eq 0x20b) { $peOff + 24 + 112 } else { $peOff + 24 + 96 }
    $importRva = [BitConverter]::ToInt32($pe, $dirOff + 8)
    if ($importRva -eq 0) { return $names }
    function RvaToOff([byte[]]$buf, [int]$hdr, [int]$rva) {
        $nsec = [BitConverter]::ToUInt16($buf, $hdr + 6)
        $opt = [BitConverter]::ToUInt16($buf, $hdr + 20)
        $sec = $hdr + 24 + $opt
        for ($i = 0; $i -lt $nsec; $i++) {
            $s = $sec + $i * 40
            $vs = [BitConverter]::ToInt32($buf, $s + 8)
            $va = [BitConverter]::ToInt32($buf, $s + 12)
            $raw = [BitConverter]::ToInt32($buf, $s + 20)
            $size = if ($vs -gt 0) { $vs } else { [BitConverter]::ToInt32($buf, $s + 16) }
            if ($rva -ge $va -and $rva -lt ($va + $size)) { return $raw + ($rva - $va) }
        }
        throw "rva $rva"
    }
    function ReadZ([byte[]]$buf, [int]$off) {
        $n = 0
        while (($off + $n) -lt $buf.Length -and $buf[$off + $n] -ne 0) { $n++ }
        return [System.Text.Encoding]::ASCII.GetString($buf, $off, $n)
    }
    $importOff = RvaToOff $pe $peOff $importRva
    for ($desc = $importOff; ($desc + 20) -le $pe.Length; $desc += 20) {
        $lookup = [BitConverter]::ToInt32($pe, $desc)
        $nameRva = [BitConverter]::ToInt32($pe, $desc + 12)
        $iat = [BitConverter]::ToInt32($pe, $desc + 16)
        if ($lookup -eq 0 -and $nameRva -eq 0 -and $iat -eq 0) { break }
        $thunkRva = if ($lookup -ne 0) { $lookup } else { $iat }
        $thunk = RvaToOff $pe $peOff $thunkRva
        $stride = if ($magic -eq 0x20b) { 8 } else { 4 }
        for ($t = $thunk; ($t + $stride) -le $pe.Length; $t += $stride) {
            $entry = if ($stride -eq 8) { [BitConverter]::ToInt64($pe, $t) } else { [BitConverter]::ToUInt32($pe, $t) }
            if ($entry -eq 0) { break }
            $ordbit = if ($stride -eq 8) { [int64]0x8000000000000000 } else { 0x80000000 }
            if (($entry -band $ordbit) -ne 0) { continue }
            $hint = RvaToOff $pe $peOff ([int]($entry -band 0x7fffffff))
            [void]$names.Add((ReadZ $pe ($hint + 2)))
        }
    }
    return $names
}

function Assert-NoDangerIat([string]$Label, [string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $imp = Get-PeImportNames $bytes
    Write-Output ("iat_dump " + $Label + " " + ($imp -join ","))
    foreach ($bad in @("LoadLibraryA", "GetProcAddress", "CreateProcessA", "CreateProcessW", "WinExec", "ShellExecuteA")) {
        if ($imp -contains $bad) { throw "$Label IAT contains $bad" }
    }
}

Assert-NoDangerIat "health" $exe
$pe = [System.IO.File]::ReadAllBytes($exe)
$ascii = [System.Text.Encoding]::ASCII.GetString($pe)
$healthImp = Get-PeImportNames $pe
if ($ascii -notmatch "ws2_32.dll") { throw "PE missing ws2_32.dll" }
if ($healthImp -notcontains "WSAStartup") { throw "health IAT missing WSAStartup" }
if ($healthImp -contains "LoadLibraryA") { throw "health IAT has LoadLibraryA" }
Write-Output "health_pe_iat ws2_32.dll WSAStartup (no LoadLibraryA/GetProcAddress)"

$helloSrc = Join-Path $Data "guest-hello.vire"
if (-not (Test-Path $helloSrc)) { Copy-Item (Join-Path $Root "guest-hello.vire") $helloSrc -Force }
$helloHex = Join-Path $Data "iat-hello.hex"
$helloExe = Join-Path $Data "iat-hello.exe"
if (Test-Path $helloHex) { Remove-Item -Force $helloHex }
$hp = Start-Process -FilePath $gen1 -ArgumentList @("data/guest-hello.vire", "data/iat-hello.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($hp.ExitCode -ne 0) { throw "gen1 hello compile exit $($hp.ExitCode)" }
Convert-HexToExe $helloHex $helloExe
Assert-NoDangerIat "hello" $helloExe
Assert-NoDangerIat "compiler" $gen1

$badVire = Join-Path $Data "bad-resolve.vire"
Set-Content -Path $badVire -Value "define main`n  LoadLibraryA with `"kernel32.dll`"`nend`n"
$badHex = Join-Path $Data "bad-resolve.hex"
$bp = Start-Process -FilePath $gen1 -ArgumentList @("data/bad-resolve.vire", "data/bad-resolve.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($bp.ExitCode -eq 0) { throw "non-allowlisted resolve compiled" }
Write-Output "inexpressible_resolve exit $($bp.ExitCode)"

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
    if ($server.HasExited) {
        $so = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
        $se = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
        Write-Output ("health_server_out " + $so)
        Write-Output ("health_server_err " + $se)
        throw "health server exited $($server.ExitCode) early"
    }
    Start-Sleep -Milliseconds 100
}
if (-not $port) {
    $so = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
    Write-Output ("health_server_out " + $so)
    throw "did not print listening port"
}
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

$kids = @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $server.Id })
Write-Output ("child_process_count " + $kids.Count)
if ($kids.Count -gt 0) {
    throw ("health PE spawned child process: " + (($kids | ForEach-Object { $_.Name + ":" + $_.ProcessId }) -join ","))
}

try { $server.Kill() } catch { }
Write-Output "native net windows ok"
