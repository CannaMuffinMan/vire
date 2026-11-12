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
$peHex = ([System.BitConverter]::ToString($pe) -replace "-", "")
if ($peHex -notmatch "E9F51000009090") { throw "guest PE missing hu_frame jump e9f51000009090" }
if ($ascii -notlike "*content-length:*") { throw "guest PE missing content-length: needle" }
if ($ascii -notlike "*transfer-encoding:*") { throw "guest PE missing transfer-encoding: needle" }
Write-Output "health_pe_iat ws2_32.dll WSAStartup (no LoadLibraryA/GetProcAddress)"
Write-Output "health_pe_hu_frame jump+needles present"

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
Start-Sleep -Milliseconds 400
if ($server.HasExited) { throw "health server exited $($server.ExitCode) after listen" }

function Convert-BytesToHex([byte[]]$Bytes) {
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return "" }
    $n = [Math]::Min(512, $Bytes.Length)
    $slice = New-Object byte[] $n
    [Array]::Copy($Bytes, $slice, $n)
    $hex = ([System.BitConverter]::ToString($slice) -replace "-", "")
    if ($Bytes.Length -gt 512) { $hex = $hex + "...trunc" }
    return $hex
}

function Convert-BytesToAscii([byte[]]$Bytes) {
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return "" }
    $n = [Math]::Min(512, $Bytes.Length)
    $chars = New-Object char[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $b = $Bytes[$i]
        $chars[$i] = [char]$(if ($b -ge 32 -and $b -le 126) { $b } else { 46 })
    }
    $s = New-Object string (,$chars)
    if ($Bytes.Length -gt 512) { $s = $s + "...trunc" }
    return $s
}

function Send-RawBytes([int]$Port, [byte[]]$Payload, [int]$WaitMs = 3000) {
    $client = New-Object System.Net.Sockets.TcpClient
    $client.ReceiveTimeout = $WaitMs
    $client.SendTimeout = $WaitMs
    $client.Connect("127.0.0.1", $Port)
    $stream = $client.GetStream()
    $stream.Write($Payload, 0, $Payload.Length)
    $buf = New-Object byte[] 8192
    $n = 0
    try { $n = $stream.Read($buf, 0, $buf.Length) } catch { $n = 0 }
    $client.Close()
    if ($n -le 0) { return ,[byte[]]@() }
    $out = New-Object byte[] $n
    [Array]::Copy($buf, $out, $n)
    return ,$out
}

function Send-Raw([int]$Port, [string]$Payload, [int]$WaitMs = 3000) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Payload)
    $resp = Send-RawBytes $Port $bytes $WaitMs
    return Convert-BytesToAscii $resp
}

function Write-AdversaryWire([string]$Name, [byte[]]$Request, [byte[]]$Response) {
    Write-Host ("adversary_{0}_request_len {1}" -f $Name, $Request.Length)
    Write-Host ("adversary_{0}_request_hex {1}" -f $Name, (Convert-BytesToHex $Request))
    Write-Host ("adversary_{0}_request_ascii {1}" -f $Name, (Convert-BytesToAscii $Request))
    Write-Host ("adversary_{0}_response_len {1}" -f $Name, $Response.Length)
    Write-Host ("adversary_{0}_response_hex {1}" -f $Name, (Convert-BytesToHex $Response))
    Write-Host ("adversary_{0}_response_ascii {1}" -f $Name, (Convert-BytesToAscii $Response))
}

function Assert-AdversaryStatus([string]$Name, [byte[]]$Request, [string]$WantStatus) {
    $resp = Send-RawBytes $port $Request
    Write-AdversaryWire $Name $Request $resp
    $text = Convert-BytesToAscii $resp
    $prefix = "HTTP/1.1 $WantStatus "
    if ($text.Length -lt $prefix.Length -or $text.Substring(0, $prefix.Length) -cne $prefix) {
        throw ("{0} expected {1}, got {2}" -f $Name, $WantStatus, $text)
    }
    if ($text -notmatch "(?i)connection:\s*close") { throw "$Name missing Connection: close" }
    return $text
}

$health = Send-Raw $port "GET /health HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n"
if (-not $health) {
    $curl = & curl.exe -s -S -D - --max-time 5 "http://127.0.0.1:$port/health" 2>&1 | Out-String
    Write-Output "health_curl_exe $curl"
    $so = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
    $se = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
    Write-Output ("health_server_out " + $so)
    Write-Output ("health_server_err " + $se)
    Write-Output ("health_server_exited " + $server.HasExited + " " + $(if ($server.HasExited) { $server.ExitCode } else { "running" }))
    foreach ($ripFile in @((Join-Path $Root "crash-rip.txt"), (Join-Path $Data "crash-rip.txt"), (Join-Path $Root "data/crash-rip.txt"))) {
        if (Test-Path $ripFile) { Write-Output ("crash_rip_file " + $ripFile + " " + ((Get-Content -Raw $ripFile) -replace '\s+', ' ')) }
    }
    $health = $curl
}
Write-Output "health_curl_result $health"
function Get-JsonBody([string]$Raw) {
    if ($Raw -notmatch '(?s)(\{.*\})\s*$') { return "" }
    return $Matches[1].Trim()
}
$want = '{"ok":true,"service":"fcgcpa","payments":false}'
if ($health -notmatch "HTTP/1.1 200 ") { throw "health status not 200" }
if ($health -notmatch "(?i)content-type:\s*application/json") { throw "health content-type not application/json" }
$healthBody = Get-JsonBody $health
if ($healthBody -cne $want) { throw "health body contract mismatch: $healthBody" }
if ($health -match "(?i)set-cookie") { throw "unexpected set-cookie" }
Write-Output "contract_health_status 200"
Write-Output "contract_health_content_type application/json"
Write-Output "contract_health_body $healthBody"
Write-Output "contract_source fcgcpa-prod main 5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4 inventory (unauth GET /health and GET /api/health) plus in-tree api/fcgcpa.vire body fields; this token cannot re-open the private Node handler"

$apiHealth = Send-Raw $port "GET /api/health HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n"
Write-Output "api_health_curl_result $apiHealth"
if ($apiHealth -notmatch "HTTP/1.1 200 ") { throw "api/health status not 200" }
if ($apiHealth -notmatch "(?i)content-type:\s*application/json") { throw "api/health content-type not application/json" }
$apiBody = Get-JsonBody $apiHealth
if ($apiBody -cne $want) { throw "api/health body contract mismatch: $apiBody" }
Write-Output "contract_api_health_status 200"
Write-Output "contract_api_health_content_type application/json"
Write-Output "contract_api_health_body $apiBody"

$malReq = [System.Text.Encoding]::ASCII.GetBytes("GET /health`r`n`r`n")
[void](Assert-AdversaryStatus "malformed_line" $malReq "400")

# Exactly 16384 bytes, no leftover write after the 16KiB header cap, so
# closesocket cannot RST and drop the 431.
$huge = "GET / HTTP/1.1`r`nHost: x`r`n"
$pad = "X: " + ("y" * 240) + "`r`n"
while ($huge.Length + $pad.Length -le 16384) { $huge += $pad }
if ($huge.Length -lt 16384) { $huge += "Z" * (16384 - $huge.Length) }
$hugeBytes = [System.Text.Encoding]::ASCII.GetBytes($huge)
[void](Assert-AdversaryStatus "oversize_headers" $hugeBytes "431")

# Well-formed GET /health with extra request fields. RFC 9112 allows them.
# 200 is required. Request Set-Cookie must not appear in the response.
$injectReq = [System.Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nHost: x`r`nX-Foo: bar`r`nSet-Cookie: stolen`r`n`r`n")
$injectText = Assert-AdversaryStatus "crlf_request_header" $injectReq "200"
Write-Output "adversary_crlf_request_header $injectText"
if ($injectText -match "(?i)set-cookie: stolen") { throw "request header leaked into response" }
if ($injectText -notmatch "(?i)content-type:\s*application/json") { throw "crlf_request_header content-type" }
$injectBody = Get-JsonBody $injectText
if ($injectBody -cne $want) { throw "crlf_request_header body $injectBody" }

# RFC 9112: request line and field lines are CR LF. Bare LF, lone CR,
# CR inside a field value, and obs-fold are malformed -> 400 and close.
[void](Assert-AdversaryStatus "bare_lf" ([System.Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`nHost: x`r`n`r`n")) "400")
[void](Assert-AdversaryStatus "lone_cr" ([System.Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`rHost: x`r`n`r`n")) "400")
[void](Assert-AdversaryStatus "cr_in_header_value" ([System.Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nHost: x`ry`r`n`r`n")) "400")
[void](Assert-AdversaryStatus "obs_fold" ([System.Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nHost: x`r`nX-Foo: bar`r`n folded`r`n`r`n")) "400")
[void](Assert-AdversaryStatus "dup_content_length" ([System.Text.Encoding]::ASCII.GetBytes("POST /health HTTP/1.1`r`nHost: x`r`nContent-Length: 0`r`nContent-Length: 5`r`n`r`nhello")) "400")
[void](Assert-AdversaryStatus "te_and_content_length" ([System.Text.Encoding]::ASCII.GetBytes("POST /health HTTP/1.1`r`nHost: x`r`nTransfer-Encoding: chunked`r`nContent-Length: 5`r`n`r`nhello")) "501")

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
